# Domain Model: Retention Offer (Telia)

> **Stage 1 — Spec Gate** | Pipeline: RAP Pipeline Orchestrator
> **Status**: ✅ APPROVED (demo gate — human review simulated)
> **Source**: Strategic Plan v1 + domain-discovery-rap skill
> **Invariants**: 4 (all mapped to RAP enforcement mechanisms)

---

## Events

| Event | Producer | Consumer | Payload |
|-------|----------|----------|---------|
| ContractTerminationRequested | CRM (existing) | RetentionOffer BO | ContractUUID, CustomerUUID, RequestedDate |
| RetentionOfferCreated | RetentionOffer BO | Billing, CRM | OfferUUID, ContractUUID, Discount, ValidTo |
| DiscountCalculated | RetentionOffer BO | CRM (UI) | OfferUUID, Discount, ARPU, Segment |
| ApprovalRequested | RetentionOffer BO | Approval Workflow | OfferUUID, Discount, ApproverRole |
| ApprovalGranted | Approval Workflow | RetentionOffer BO | OfferUUID, Approver, Decision |
| OfferAccepted | RetentionOffer BO | Billing, CRM | OfferUUID, ContractUUID, AppliedDiscount |
| OfferRejected | RetentionOffer BO | CRM | OfferUUID, RejectionReason |
| OfferExpired | Scheduler (App Job) | RetentionOffer BO | OfferUUID, ExpiryTimestamp |

## Commands

| Command | Actor | Aggregate | Triggers Event |
|---------|-------|-----------|----------------|
| CreateOffer | CRM Agent | RetentionOffer | RetentionOfferCreated, DiscountCalculated |
| CalculateDiscount | System (determination) | RetentionOffer | DiscountCalculated |
| RequestApproval | System (determination) | RetentionOffer | ApprovalRequested |
| AcceptOffer | CRM Agent | RetentionOffer | OfferAccepted |
| RejectOffer | CRM Agent | RetentionOffer | OfferRejected |
| ExpireOffer | Scheduler (App Job) | RetentionOffer | OfferExpired |
| (Auto) CheckActiveOffer | System (validation) | RetentionOffer | — (prevents RetentionOfferCreated) |

## Aggregates (RAP Business Objects)

### RetentionOffer (Root)

| Entity | Key | Parent | Fields |
|--------|-----|--------|--------|
| RetentionOffer | OfferUUID (UUID) | — | ContractUUID, CustomerUUID, Discount, OfferStatus, ValidFrom, ValidTo, ApprovalStatus, ApprovalThresholdAtCreation, ARPU, Segment, ContractLifetime, LastChangedAt, LastChangedBy, CreatedAt, CreatedBy |
| RetentionOfferReason | ItemUUID (UUID) | RetentionOffer | ReasonCode, ReasonText |
| RetentionOfferApproval | ApprovalUUID (UUID) | RetentionOffer | Approver, ApprovalTimestamp, Decision, Comment |

**Aggregate root**: RetentionOffer
**Consistency boundary**: All invariants enforced within this aggregate
**Draft**: Enabled (CRM agent interaction pattern — BDEF-007 justified)

## Invariants → Enforcement Mapping

| # | Invariant | Type | Enforcement Point | RAP Mechanism |
|---|-----------|------|-------------------|----------------|
| 1 | Discount ≤ 30% | Validation | `validateDiscountCeiling` | `validation validateDiscountCeiling on save { field Discount; }` — hard reject with message ZMS_RET_OFF 001 |
| 2 | 72h validity | Determination + Job | `determineExpiry` + App Job sweep | `determination determineExpiry on modify { create; }` sets ValidTo = CreatedAt + 72h; scheduled job `ZAPP_JOB_RET_EXPIRY` sweeps expired offers every 15min |
| 3 | One active offer per contract | Validation + Lock | `validateSingleActiveOffer` | `validation validateSingleActiveOffer on save { field ContractUUID; }` — READ ENTITY checks active offers; `lock master total etag LastChangedAt` prevents concurrent creation |
| 4 | Approval above threshold | Determination + Action | `determineApprovalRequired` + `action requestApproval` | `determination determineApprovalRequired on modify { field Discount; }` — if Discount > threshold (from ZRET_OFFER_THR), sets ApprovalStatus = PENDING; `action requestApproval result [1] $self` triggers workflow; `validation validateApprovalStatus on save` blocks activation if PENDING |

> **Design note (for Stage 5 — Understanding Ritual)**: Invariant #3 uses a **validation** (not a determination) because it must *prevent* creation — a determination only fires after modify/create. The lock on ContractUUID ensures pessimistic concurrency at DB level, but the validation is the actual invariant enforcer — the lock prevents the race, the validation enforces the rule.

## Bounded Context Boundaries

| Context | Owns | References | Integration |
|---------|------|------------|-------------|
| CRM (existing) | Contract, Customer, Interaction History | RetentionOffer (via association) | CDS association (read-only) |
| Billing (external) | Invoice, Tariff, Discount Application | RetentionOffer (read via API) | Released REST API (sync) |
| Retention (new) | RetentionOffer, RetentionOfferReason, RetentionOfferApproval, Approval Threshold Config | Contract (read), Customer (read), Interaction History (read) | CDS associations for CRM; REST for Billing |
| Workflow (existing) | Approval routing, Approver assignment | RetentionOffer (action trigger) | SAP standard workflow (async) |

**Key boundary rule**: RetentionOffer BO never copies customer personal data into its own tables. All personal data is accessed via CDS association to ZI_Customer. This is the GDPR boundary.

## Integration Contracts

| Contract | Direction | Mechanism | Error Handling |
|---------|-----------|-----------|----------------|
| Billing.CalculateDiscount | Outbound | Sync REST (determination on modify) | CX class ZCX_BILLING_ERROR; retry 3x with backoff; on final failure: set offer status to ERROR, report to agent via `reported` |
| Billing.ApplyDiscount | Outbound | Sync REST (action acceptOffer) | Idempotency key = OfferUUID; CX class ZCX_BILLING_ERROR; compensation: if API succeeds but RAP save fails, idempotency key prevents double-application on retry |
| CRM.Contract (association) | Inbound | CDS association (ZI_Contract) | Read-only; no error handling needed (RAP handles auth) |
| CRM.Customer (association) | Inbound | CDS association (ZI_Customer) | Read-only; GDPR auth check enforced via @AccessControl |
| CRM.InteractionHistory (association) | Inbound | CDS association (ZI_Interaction) | Read-only; lookback 12 months for complaint history |
| Approval.Workflow | Outbound/Inbound | RAP action → SAP Workflow (async) | Timeout: 48h escalation to manager; rejection: offer status → REJECTED |
| Expiry.ApplicationJob | Internal | Scheduled ABAP Job (every 15min) | Log failures to BAL; retry on next sweep; offers with ValidTo < now → status EXPIRED |

---

## Human Gate — Approval

> **This domain model is the single gate before code generation.**
> The human reviews this one page — not 15+ generated files.
> In a real pipeline run, the developer marks this as `APPROVED` and Stage 2 begins.
>
> **Demo status**: ✅ APPROVED — proceeding to Stage 2 (rap-abap-manager)
