# Strategic Plan: Telecom Retention Offer (CRM Churn Retention Enhancement)

> **Stage 1 — Spec Gate** | Pipeline: RAP Pipeline Orchestrator  
> **Client**: Telia (demo/proof case)  
> **System**: SAP S/4HANA 2023 FPS01  
> **Status**: Ready for input to `domain-discovery-rap` (Stage 2)

---

## Task Decomposition

| Component | Type | Layer | Dependencies |
|-----------|------|-------|--------------|
| ZI_RetentionOffer | CDS View (root entity) | Interface | zret_offer (DB table), ZI_Contract, ZI_Customer |
| ZI_RetOfferReason | CDS View (child entity) | Interface | zret_offer_reason (DB table), ZI_RetentionOffer |
| ZI_RetOfferApproval | CDS View (child entity) | Interface | zret_offer_approval (DB table), ZI_RetentionOffer |
| ZI_Contract | CDS View (reused/existing) | Interface | Existing CRM Contract BO (RAP-enabled) |
| ZI_Customer | CDS View (reused/existing) | Interface | Existing CRM Customer BO (RAP-enabled) |
| ZC_RetentionOffer | CDS View (root projection) | Projection | ZI_RetentionOffer |
| ZC_RetOfferReason | CDS View (child projection) | Projection | ZI_RetOfferReason |
| ZC_RetOfferApproval | CDS View (child projection) | Projection | ZI_RetOfferApproval |
| ZC_RetOfferCalcParam | CDS View (calc. params display) | Projection | ZI_RetentionOffer (computed fields) |
| ZI_RetentionOffer \| BDEF | Behavior Definition | Behavior | ZI_RetentionOffer, ZI_RetOfferReason, ZI_RetOfferApproval |
| ZBP_I_RetentionOffer | Behavior Implementation Class | Behavior | ZI_RetentionOffer BDEF, Billing REST client |
| ZC_RetentionOffer \| Metadata Extension | Metadata Extension (UI) | Consumption | ZC_RetentionOffer |
| ZC_RetOfferReason \| Metadata Extension | Metadata Extension (UI) | Consumption | ZC_RetOfferReason |
| ZC_RetOfferApproval \| Metadata Extension | Metadata Extension (UI) | Consumption | ZC_RetOfferApproval |
| ZUI_RetentionOffer | Fiori Elements App (OData V4) | Consumption | ZC_RetentionOffer service binding |
| ZUI_RET_OFFER_SDEF | Service Definition | Service | ZC_RetentionOffer |
| ZUI_RET_OFFER_SBIND | Service Binding (OData V4) | Service | ZUI_RET_OFFER_SDEF |
| ZCL_BILLING_REST_CLIENT | ABAP Class (REST client) | Integration | Billing system REST API (released) |
| ZCL_RET_DISCOUNT_CALC | ABAP Class (discount engine) | Business Logic | ZI_Contract, ZI_Customer, interaction history |
| ZCL_RET_OFFER_EXPIRY | ABAP Class (expiry handler) | Integration | Application Job (scheduled) |
| ZRET_OFFER | DB Table (persistent) | Database | — |
| ZRET_OFFER_D | DB Table (draft) | Database | ZRET_OFFER |
| ZRET_OFFER_REASON | DB Table (persistent) | Database | ZRET_OFFER |
| ZRET_OFFER_REASON_D | DB Table (draft) | Database | ZRET_OFFER_REASON |
| ZRET_OFFER_APPROVAL | DB Table (persistent) | Database | ZRET_OFFER |
| ZRET_OFFER_APPROVAL_D | DB Table (draft) | Database | ZRET_OFFER_APPROVAL |
| ZRET_OFFER_THR | DB Table (config: approval threshold) | Database | — |
| ZAPP_JOB_RET_EXPIRY | Application Job (expiry sweep) | Operations | ZCL_RET_OFFER_EXPIRY |
| ZAUTH_RET_OFF | Authorization Object | Security | — |
| ZMS_RET_OFF | Message Class (messages) | Messaging | — |

---

## Integration Points

| Direction | System/API | Type | Sync/Async | Released? |
|-----------|-----------|------|------------|-----------|
| Outbound | Billing System — `/Billing/CalculateDiscount` (POST) | REST | Sync | Yes |
| Outbound | Billing System — `/Billing/ApplyDiscount` (POST) | REST | Sync | Yes |
| Outbound | Billing System — `/Contract/Validate` (GET) | REST | Sync | Yes |
| Inbound | CRM Contract BO (existing RAP BO) | RAP / CDS Association | Sync | Yes (RAP-enabled) |
| Inbound | CRM Customer BO (existing RAP BO) | RAP / CDS Association | Sync | Yes (RAP-enabled) |
| Inbound | CRM Interaction/Complaint History (existing) | CDS View / RAP Read | Sync | Yes |
| Inbound | Approval Workflow — SAP S/4HANA Advanced Approval | RAP Action → Workflow | Async | Yes (standard S/4 workflow) |
| Internal | Application Job — Offer expiry sweep | ABAP Job | Async | N/A (internal) |
| Outbound | Audit Log (personal data access logging) | BAL / Application Log | Sync | Yes (standard API) |

> **Note on released APIs**: The scenario states the Billing system exposes a released REST API. No unreleased APIs are required. If the billing API were unreleased, this would be a **hard blocker** and must be escalated to human review before proceeding to Stage 2.

---

## Risk Register

| # | Risk | Dimension | Impact | Likelihood | Mitigation |
|---|------|-----------|--------|------------|------------|
| 1 | Concurrent offer creation on the same contract — two CRM agents creating offers simultaneously for one contract | Lifecycle | High | Medium | `lock master total etag` on Contract UUID; validation `validateSingleActiveOffer on save` checks active offers via `READ ENTITY` before persisting; pessimistic lock prevents parallel writes |
| 2 | Billing API timeout or unavailability during discount calculation in the save sequence | Integration | High | Medium | Design discount calculation as a determination `on modify` (pre-save), not in `save` — if billing API fails, the determination fails and the offer is not saved; display error to agent via `reported`; no partial persistence. Consider local caching of ARPU segment for offline calculation fallback |
| 3 | Discount exceeds 30% due to calculation rounding or manual override | Data Model | High | Low | Validation `validateDiscountCeiling on save { field Discount; }` with hard assertion `Discount <= 30`; reject with message class ZMS_RET_OFF; field is `readonly` after calculation unless re-calculated |
| 4 | Offer not expired — 72-hour window exceeded but offer still shows as active | Lifecycle | Medium | Medium | Scheduled Application Job runs every 15 minutes; determination `determineExpiry on modify { create; }` sets `ValidTo` timestamp at creation; job sweeps expired offers and sets status to `Expired`; also lazy expiry check on read (determination `on modify` if `sy-datum > ValidTo`) |
| 5 | GDPR-relevant customer fields (name, contact, address) exposed in offer entity or logs | Compliance | High | Medium | All personal data accessed via CDS association to `ZI_Customer` (never copied into `ZRET_OFFER` table); `@AccessControl.authorizationCheck: #CHECK_REQUIRED` on all CDS views exposing customer data; `READ ENTITY` for customer data (never direct `SELECT`); no personal data in `reported` messages — use pseudonymized contract ID; audit log entry on every personal data access (who, when, what record, why) |
| 6 | Billing API idempotency — `ApplyDiscount` called twice due to retry, resulting in double discount application | Integration | High | Low | Idempotency key sent with each billing API call (Offer UUID); billing system must support idempotency check; RAP `save` sequence tracks whether billing call was successful before marking offer `Applied`; compensation logic on failure |
| 7 | Approval threshold configuration changes while offers are in-flight | Lifecycle | Medium | Low | Approval threshold read at offer creation time and stored as snapshot on the offer record (`ApprovalThresholdAtCreation`); subsequent threshold changes do not affect in-flight offers; only new offers use updated threshold |
| 8 | Table `ZRET_OFFER` grows unbounded — expired/used offers accumulate | Data Model | Medium | High | Archiving strategy: offers older than 24 months with status `Expired` or `Rejected` are archived; anonymize personal data references before archiving (GDPR-005); partition considerations for large volumes; retention period configurable |
| 9 | N+1 read pattern when Fiori app loads offer list with customer and contract details | Performance | Medium | High | CDS associations with proper joins; projection views use association-based reads (not per-record `READ ENTITY` calls); consider materialized/analytical view for bulk reporting; limit default page size to 50; implement `@ObjectModel.resultSize` |
| 10 | No audit trail for personal data access via Fiori app | Compliance | High | Medium | Audit log entry created on every `READ` of offers containing personal data associations; log fields: user ID, timestamp, contract ID, access purpose (offer management); BAL log with pseudonymized identifiers |
| 11 | Missing authorization check — agent can view/modify offers for contracts outside their scope | Compliance | High | Medium | Authorization object `ZAUTH_RET_OFF` with instance-level check on sales org / service team; `authorization master ( instance )` in BDEF; access-controlled CDS views; test with negative authorization test cases |
| 12 | Bulk offer creation (e.g., proactive retention campaign) causes lock contention on `ZRET_OFFER` table | Performance | Medium | Low | Separate campaign/bulk path from interactive CRM agent path; batch processing uses enqueue-free pattern with `COMMIT WORK` batches; interactive path uses standard RAP locking; do not mix batch and interactive in same transaction |

---

## Implementation Approach

### BO Type: Managed (with hybrid save for billing integration)

- **Primary entity (ZI_RetentionOffer)**: **Managed** implementation. Standard CRUD on custom tables (`ZRET_OFFER`). The RAP framework handles persistence for create/update of offer data.
- **Billing integration**: Discount calculation is a **determination `on modify`** (pre-save) that calls the billing REST API synchronously via `ZCL_BILLING_REST_CLIENT`. If the call fails, the determination reports an error and the offer is not saved. The `save` sequence only persists to `ZRET_OFFER` — no external calls in save (avoids partial-write risk).
- **Billing application (ApplyDiscount)**: Triggered by an **action** (`acceptOffer`) which calls the billing API. The action is **idempotent** (sends Offer UUID as idempotency key). If the billing call succeeds but RAP save fails, the idempotency key prevents double-application on retry.
- **Decision rationale**: Per BDEF-009, managed is appropriate for new BO with new tables. Billing integration is via determination/action, not custom persistence — so managed is correct. If billing `ApplyDiscount` requires transactional coordination (2-phase commit), upgrade to **unmanaged** with custom save sequence.

### Draft: Enabled

- **Justification**: CRM agent interaction pattern requires draft. Agent calculates a discount, may consult with the customer, modify the offer, get approval — all over an extended time window. Draft allows temporary persistence without committing.
- Draft tables: `ZRET_OFFER_D`, `ZRET_OFFER_REASON_D`, `ZRET_OFFER_APPROVAL_D`
- Per BDEF-007: human-interaction business justification is met (CRM agent reviews and modifies offers before activation).

### Locking

- **Lock master**: `lock master total etag LastChangedAt` on `ZI_RetentionOffer` (pessimistic lock at DB level, per BDEF-002)
- **Lock scope**: Lock on `ContractUUID` — ensures only one agent can create/modify an offer for a given contract at a time
- **ETag**: `LastChangedAt` field (`timestampl`) on all entities for optimistic concurrency validation
- **Child entities**: Inherit lock from parent (`lock dependent by association`)

### Invariant → RAP Construct Mapping (preview for Stage 2)

| Invariant | RAP Construct | Trigger |
|-----------|--------------|---------|
| 1. Discount ≤ 30% | Validation `validateDiscountCeiling` | `on save { field Discount; }` |
| 2. Offer expires after 72h | Determination `determineExpiry` + Application Job | `on modify { create; }` + scheduled sweep |
| 3. One active offer per contract | Validation `validateSingleActiveOffer` | `on save { field ContractUUID; }` + `lock master` on ContractUUID |
| 4. Approval above threshold | Action `requestApproval` → Workflow; Validation `validateApprovalStatus` | `on save` for activation |

---

## Open Questions for Human Review

1. **Discount calculation algorithm**: The scenario lists three inputs (ARPU segment, contract lifetime, interaction/complaint history) but does not specify the calculation formula. What are the exact weights and breakpoints? Is there an existing calculation engine, or does the business want a configurable rules table?

2. **Approval workflow integration**: Should approval use SAP S/4HANA standard workflow (Business Workflow / BTP Workflow), or a custom approval screen within the same Fiori app? Who are the approvers — first-line manager, finance, or a dedicated retention team?

3. **Billing system contract**: The billing REST API is described as "released," but what are the SLA guarantees (response time, availability)? If the API has >2s response time, the synchronous determination approach may need reconsideration (async pattern with status polling).

4. **ARPU data source**: Is ARPU segment stored in the CRM system (RAP-accessible) or only in the billing system? If only in billing, every offer creation requires a billing API call for ARPU — impacts performance and availability coupling.

5. **Interaction/complaint history access**: Is interaction history available as a CDS view in the CRM system, or does it require an API call to a complaint management system? What is the lookback period for complaint history (30 days? 12 months?)?

6. **Offer acceptance flow**: When a customer accepts an offer, does the system need to immediately push the discount to the billing system (real-time contract modification), or is there a batch reconciliation at end-of-day?

7. **Multi-contract customers**: A customer may have multiple contracts (e.g., mobile + broadband). Is the retention offer per-contract or per-customer? If per-customer, invariant #3 ("one active offer per contract") needs reinterpretation.

8. **Offer rejection / counter-offer**: If a customer rejects an offer, can the agent immediately create a new (potentially different) offer, or is there a cooldown period? This affects the lifecycle state machine.

9. **Reporting and analytics**: Does the business need a separate analytical app for retention offer success rates, discount distribution, churn impact? This would require additional CDS analytical views and potentially a CDS transactional/analytical bridge.

10. **Multi-language support**: Telia operates in multiple Nordic markets. Does the Fiori app need multi-language UI and multi-language offer text? If so, this affects message class design and text table design.

11. **Data retention and right-to-be-forgotten**: What is the legal retention period for retention offer records after contract termination? Does the "right to be forgotten" require anonymization of the entire offer record, or only the customer reference?

12. **Integration testing environment**: Is there a sandbox billing system available for integration testing, or do we need to mock the billing API during development? This affects the testing strategy and timeline.

---

## Pipeline Handoff

- **Next Stage**: `domain-discovery-rap` (Stage 2 — Domain Model)
- **Input to Stage 2**: This strategic plan (artifact list, integration points, invariant mapping)
- **Do NOT carry forward**: Open questions remain for human resolution; Stage 2 proceeds with assumptions documented
- **Hard blockers for Stage 2**: None identified — all required APIs are released. If any open question resolution changes the API dependency to an unreleased API, escalate immediately.
