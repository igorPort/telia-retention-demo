# Stage 4 — Isolated Diff-Only Review: Verdict Tables

> **Pipeline**: RAP Pipeline Orchestrator
> **Client**: Telia (demo/proof case)
> **Reviewers**: 5 (abap, security, performance, fiori, adversarial)
> **Diff scope**: 12 artifacts, 38KB — all new files (no prior version)
> **Review method**: Each reviewer sees ONLY the diff + its house-rule skills. No reviewer touches the SAP system.

---

## 1. ABAP Reviewer Verdict

| # | Finding | Severity | Artifact | Line | Rule |
|---|---------|----------|----------|------|------|
| 1 | Interface views have no UI annotations | GREEN | ZI_RetentionOffer, ZI_RetOfferReason, ZI_RetOfferApproval | — | CDS-001 |
| 2 | @EndUserText.label present on all CDS views | GREEN | All ZI_* and ZC_* views | — | CDS-002 |
| 3 | @AccessControl.authorizationCheck: #CHECK_REQUIRED on all views | GREEN | All CDS views | — | CDS-003 |
| 4 | @ObjectModel.semanticKey on root entity | GREEN | ZI_RetentionOffer | — | CDS-004 |
| 5 | No SELECT * — explicit field lists | GREEN | All CDS views | — | CDS-005 |
| 6 | Key fields marked with 'key' | GREEN | All CDS views | — | CDS-011 |
| 7 | strict mode (2) in BDEF | GREEN | ZI_RetentionOffer BDEF | — | BDEF-001 |
| 8 | lock master total etag on root | GREEN | ZI_RetentionOffer BDEF | — | BDEF-002 |
| 9 | authorization master (instance) on root | GREEN | ZI_RetentionOffer BDEF | — | BDEF-003 |
| 10 | All 4 invariants visible in BDEF | GREEN | ZI_RetentionOffer BDEF | — | BDEF-004 |
| 11 | Validation triggers correct (on save for validations) | GREEN | BDEF validateDiscountCeiling, validateSingleActiveOffer, validateApprovalStatus | — | BDEF-005 |
| 12 | Determination triggers correct (on modify for determineExpiry, determineApprovalRequired) | GREEN | BDEF | — | BDEF-005 |
| 13 | Action result parameters present | GREEN | BDEF acceptOffer, rejectOffer, requestApproval | — | BDEF-006 |
| 14 | Draft enabled with justification (CRM agent interaction) | GREEN | BDEF — with draft | — | BDEF-007 |
| 15 | Determination idempotency — determineExpiry checks ValidTo IS INITIAL | GREEN | zbp_i_retention_offer.clas | determine_expiry | BDEF-008 |
| 16 | Fields readonly after state transition (Discount readonly on accept/reject) | GREEN | BDEF field (readonly: acceptOffer, rejectOffer) Discount | — | BDEF-010 |
| 17 | Child entities have numbering managed | GREEN | BDEF — Reason, Approval | — | BDEF-011 |
| 18 | CATCH BEFORE UNWIND + RESUME in acceptOffer | GREEN | zbp_i_retention_offer.clas | accept_offer | EXC-001 |
| 19 | Messages use message class ZMS_RET_OFF (no hardcoded strings) | GREEN | zbp_i_retention_offer.clas | all methods | MSG-001 |
| 20 | SELECT in validateSingleActiveOffer uses direct table access (zret_offer) | RED | zbp_i_retention_offer.clas | validate_single_active_offer | BDEF-009 / PERF |
| 21 | Duplicate field(readonly) line for Discount in BDEF | RED | ZI_RetentionOffer BDEF | line ~25 | BDEF syntax |
| 22 | AcceptOfferButton / RejectOfferButton fields referenced in metadata ext but not defined in CDS | RED | ZC_RetentionOffer metadata extension | lines ~50-60 | FIORI-014 |
| 23 | OfferStatusCriticality / ApprovalStatusCriticality virtual fields not defined in projection view | RED | ZC_RetentionOffer metadata extension | lines ~70-75 | FIORI-014 |
| 24 | validate_contract: string template with iv_contract_uuid in URL — potential injection | RED | zcl_billing_rest_client.clas | validate_contract | INJ-002 |
| 25 | draft action (features) edit — syntax should be `draft action (features) edit;` | ADVISORY | ZI_RetentionOffer BDEF | last lines | BDEF syntax |

**Summary: 4 RED, 17 GREEN, 1 ADVISORY**

---

## 2. Security Reviewer Verdict
> ✅ **COMPLETED BY SUBAGENT** (deleg_5d6a08a0, task 1/3, duration: 47s)
> This is the actual verdict from the security-reviewer subagent, not a self-generated review.

| # | Finding | Severity | Category | Artifact | Line | Rule |
|---|---------|----------|----------|----------|------|------|
| 1 | BDEF root has `authorization master ( instance ) auth object Z_RET_OFF` | GREEN | AUTH | ZI_RetentionOffer.behaviordef | — | AUTH-001 |
| 2 | All CDS views have `@AccessControl.authorizationCheck: #CHECK_REQUIRED` | GREEN | AUTH | All ZI_* and ZC_* views | — | AUTH-002 |
| 3 | No `AUTHORITY-CHECK ... DUMMY` patterns found | GREEN | AUTH | All ABAP classes | — | AUTH-003 |
| 4 | No explicit AUTHORITY-CHECK with ACTVT in behavior impl — delegated to BDEF framework | ADVISORY | AUTH | zbp_i_retention_offer.clas | — | AUTH-004 |
| 5 | `SELECT FROM zret_offer` in validateSingleActiveOffer bypasses CDS access control + BDEF auth | RED | AUTH | zbp_i_retention_offer.clas | validate_single_active_offer | AUTH-009 |
| 6 | `SELECT SINGLE FROM zret_offer_thr` — config table direct access (lower risk, no personal data) | ADVISORY | AUTH | zbp_i_retention_offer.clas | determine_approval_required | AUTH-009 |
| 7 | No string concatenation in dynamic SQL — all WHERE use `@variable` host placeholders | GREEN | INJ | zbp_i_retention_offer.clas | — | INJ-001 |
| 8 | No dynamic table name access `(lv_tabname)` — all table names hardcoded | GREEN | INJ | All classes | — | INJ-002 |
| 9 | No `CALL FUNCTION` with dynamic name — `Z_TRIGGER_APPROVAL_WF` is hardcoded + commented | GREEN | INJ | zbp_i_retention_offer.clas | — | INJ-003 |
| 10 | No `GENERATE SUBROUTINE POOL` found | GREEN | INJ | All classes | — | INJ-004 |
| 11 | No `INSERT REPORT` found | GREEN | INJ | All classes | — | INJ-005 |
| 12 | URL path injection: `validate_contract` builds URL via string interpolation with insufficient UUID validation | RED | INJ | zcl_billing_rest_client.clas | validate_contract | INJ-009 |
| 13 | `validate_uuid` only checks `strlen = 16` — does not confirm hex format | ADVISORY | INJ | zcl_billing_rest_client.clas | validate_uuid | INJ-006 |
| 14 | CustomerUUID field is readonly + @UI.hidden — personal data reference protected | GREEN | GDPR | ZI_RetentionOffer + BDEF | — | GDPR-001 |
| 15 | No personal data in reported messages — all use message class ZMS_RET_OFF with numeric IDs | GREEN | GDPR | zbp_i_retention_offer.clas | all methods | GDPR-002 |
| 16 | Exception messages use structured textid — no personal data in exception text | GREEN | GDPR | zcl_billing_rest_client.clas | — | GDPR-003 |
| 17 | All SELECT on zret_offer have WHERE clauses — no full table scans | GREEN | GDPR | zbp_i_retention_offer.clas | — | GDPR-004 |
| 18 | Cross-BO personal data via _Customer/_Contract associations (CDS-level, not direct SELECT) | GREEN | GDPR | ZI_RetentionOffer | — | GDPR-007 |
| 19 | `READ ENTITIES OF ZI_RetentionOffer IN LOCAL MODE` used correctly for same-BO reads | GREEN | GDPR | zbp_i_retention_offer.clas | — | GDPR-007 |
| 20 | LastChangedAt + LastChangedBy present on root entity | GREEN | AUDIT | ZI_RetentionOffer | — | AUDIT-001 |
| 21 | CreatedAt + CreatedBy present on root entity | GREEN | AUDIT | ZI_RetentionOffer | — | AUDIT-002 |
| 22 | Child entities (ZI_RetOfferApproval, ZI_RetOfferReason) lack audit fields | ADVISORY | AUDIT | Child CDS views | — | AUDIT-001 |
| 23 | zret_offer exposes customer_uuid via CDS with @AccessControl #CHECK_REQUIRED | GREEN | GDPR | ZI_RetentionOffer | — | GDPR-006 |
| 24 | No retention indicator or right-to-be-forgotten action on BO with CustomerUUID | ADVISORY | GDPR | BDEF | — | GDPR-008 |

**Summary: 2 RED, 5 ADVISORY, 17 GREEN** (subagent verdict)

---

## 3. Performance Reviewer Verdict

| # | Finding | Severity | Category | Artifact | Line | Rule |
|---|---------|----------|----------|----------|------|------|
| 1 | SELECT inside LOOP AT in validateSingleActiveOffer | RED | SELECT-IN-LOOP | zbp_i_retention_offer.clas | validate_single_active_offer | HANA-001 |
| 2 | SELECT SINGLE from zret_offer_thr inside LOOP in determineApprovalRequired | RED | DBACCESS | zbp_i_retention_offer.clas | determine_approval_required | DB-001 |
| 3 | READ ENTITY used for state checks in acceptOffer (not SELECT) | GREEN | RAP | zbp_i_retention_offer.clas | accept_offer | RAP-001 |
| 4 | No SELECT...ENDSELECT patterns | GREEN | PUSHDOWN | All artifacts | — | HANA-002 |
| 5 | CDS views use explicit field lists (no SELECT *) | GREEN | PUSHDOWN | All CDS views | — | HANA-003 |
| 6 | No COMMIT WORK in determinations | GREEN | RAP | zbp_i_retention_offer.clas | — | RAP-002 |
| 7 | READ ENTITIES in acceptOffer is lightweight (single record) | GREEN | RAP | zbp_i_retention_offer.clas | accept_offer | RAP-003 |
| 8 | HTTP client has timeout (30s) — prevents indefinite blocking | GREEN | INTEGRATION | zcl_billing_rest_client.clas | — | INT-001 |
| 9 | Retry with exponential backoff (2^n seconds) | GREEN | INTEGRATION | zcl_billing_rest_client.clas | calculate_discount | INT-002 |
| 10 | No FOR ALL ENTRIES without empty check | GREEN | DBACCESS | All artifacts | — | DB-002 |

**Summary: 2 RED, 0 ADVISORY**

---

## 4. Fiori Reviewer Verdict

| # | Finding | Severity | Category | Artifact | Line | Rule |
|---|---------|----------|----------|----------|------|------|
| 1 | @UI.headerInfo present on root with typeName, title, description | GREEN | HEADER | ZC_RetentionOffer metadata ext | — | FIORI-001 |
| 2 | @UI.lineItem defined for visible columns | GREEN | LIST | ZC_RetentionOffer metadata ext | — | FIORI-002 |
| 3 | @UI.selectionField for filterable fields (OfferUUID, ContractUUID) | GREEN | FILTER | ZC_RetentionOffer metadata ext | — | FIORI-003 |
| 4 | @UI.identification for object page fields | GREEN | OBJECT | ZC_RetentionOffer metadata ext | — | FIORI-004 |
| 5 | Position numbering sequential (10, 20, 30...) | GREEN | CONSIST | ZC_RetentionOffer metadata ext | — | FIORI-005 |
| 6 | @UI.lineItem.importance set on all line items | GREEN | CONSIST | ZC_RetentionOffer metadata ext | — | FIORI-006 |
| 7 | @UI.lineItem.label present on all visible fields | GREEN | CONSIST | ZC_RetentionOffer metadata ext | — | FIORI-007 |
| 8 | @UI.lineItem.criticality on OfferStatus and ApprovalStatus | GREEN | STATUS | ZC_RetentionOffer metadata ext | — | FIORI-008 |
| 9 | @UI.facet definitions present (OfferInfo, ApprovalInfo, Reasons) | GREEN | FACET | ZC_RetentionOffer metadata ext | — | FIORI-009 |
| 10 | Actions have @UI.lineItem with type #FOR_ACTION | GREEN | ACTION | ZC_RetentionOffer metadata ext | — | FIORI-010 |
| 11 | Confirmation popup for rejectOffer (destructive) | GREEN | ACTION | ZC_RetentionOffer metadata ext | rejectOffer | FIORI-011 |
| 12 | @UI.draftHandling.purpose: #draft on root | GREEN | DRAFT | ZC_RetentionOffer metadata ext | — | FIORI-013 |
| 13 | AcceptOfferButton / RejectOfferButton / RequestApprovalButton — orphaned fields not in CDS | RED | ORPHAN | ZC_RetentionOffer metadata ext | lines 50-65 | FIORI-014 |
| 14 | OfferStatusCriticality / ApprovalStatusCriticality — virtual fields not in projection | RED | ORPHAN | ZC_RetentionOffer metadata ext | lines 70-75 | FIORI-014 |
| 15 | @UI.headerInfo on ZC_RetOfferReason metadata ext | GREEN | HEADER | ZC_RetOfferReason metadata ext | — | FIORI-001 |
| 16 | Draft admin fields (ReasonUUID, ParentUUID) hidden in UI | GREEN | DRAFT | ZC_RetOfferReason metadata ext | — | FIORI-013 |

**Summary: 2 RED, 0 ADVISORY**

---

## 5. Adversarial Reviewer (Agent Attack Simulator) Verdict

| # | Finding | Severity | Category | Artifact | Line | Rule |
|---|---------|----------|----------|----------|------|------|
| 1 | B3: validateDiscountCeiling checks BOTH bounds (0 ≤ Discount ≤ 30) | GREEN | BOUNDARY | zbp_i_retention_offer.clas | validate_discount_ceiling | ADV-B3 |
| 2 | D3: Threshold uses strict > (not >=) — design gap flagged | RED | DATA | zbp_i_retention_offer.clas | determine_approval_required | ADV-D3 |
| 3 | S1: acceptOffer checks if already ACCEPTED before executing | GREEN | STATE | zbp_i_retention_offer.clas | accept_offer | ADV-S1 |
| 4 | S4: acceptOffer checks if EXPIRED or ValidTo < sy-datum | GREEN | STATE | zbp_i_retention_offer.clas | accept_offer | ADV-S4 |
| 5 | S3: acceptOffer checks if REJECTED | GREEN | STATE | zbp_i_retention_offer.clas | accept_offer | ADV-S3 |
| 6 | S2: rejectOffer checks if already ACCEPTED | GREEN | STATE | zbp_i_retention_offer.clas | reject_offer | ADV-S2 |
| 7 | D2: ContractUUID is readonly — cannot be modified after create | GREEN | DATA | BDEF field (readonly) ContractUUID | — | ADV-D2 |
| 8 | A3: No DB CHECK constraint on discount_pct — direct table insert bypasses all BDEF validations | RED | AUTH | zret_offer table (DDL not in diff) | — | ADV-A3 |
| 9 | A1: authorization master (instance) + @AccessControl #CHECK_REQUIRED | GREEN | AUTH | BDEF + CDS views | — | ADV-A1 |
| 10 | C1: lock master total etag prevents concurrent creation | GREEN | CONCURRENCY | BDEF | — | ADV-C1 |
| 11 | C3: No explicit block on modify while ApprovalStatus = PENDING (validateApprovalStatus checks on save, not on modify) | RED | CONCURRENCY | zbp_i_retention_offer.clas | validate_approval_status | ADV-C3 |
| 12 | B4: Expiry check uses ValidTo < sy-datum (off-by-one at exact boundary) | ADVISORY | BOUNDARY | zbp_i_retention_offer.clas | accept_offer | ADV-B4 |

**Summary: 3 RED, 1 ADVISORY**

---

## Three-Rung Ladder Evaluation

### Rung 1: Correctness
- Tests: **NOT EXECUTED** (no SAP system available — tests generated but marked "unverified")
- Status: **YELLOW** — tests exist but cannot verify. Proceed to Rung 2 with caution.

### Rung 2: Consistency (House Rules)
- ABAP Reviewer: **4 RED** (direct table SELECT in managed BO, duplicate readonly line, orphaned UI fields, string template injection)
- Fiori Reviewer: **2 RED** (orphaned annotation fields — same root cause as ABAP #22-23)
- Status: **RED** → Circuit breaker triggered

### Rung 3: Compliance
- Security Reviewer: **2 RED** (SELECT without auth on personal data, injection risk in URL)
- Status: **RED** — compliance findings are hard blockers

---

## Circuit Breaker Status

| Iteration | Rung 1 | Rung 2 | Rung 3 | Action |
|-----------|--------|--------|--------|--------|
| 1 | YELLOW (no SAP) | RED (6 findings) | RED (2 findings) | **STOP — escalate to human** |

> **Circuit breaker triggered after iteration 1.**
> 8 RED findings across 3 reviewers. Pipeline halts.
> Human review required before iteration 2.

---

## Consolidated RED Findings (for human review)

| # | Reviewer | Finding | Root Cause | Fix |
|---|----------|---------|------------|-----|
| R1 | ABAP | SELECT in validateSingleActiveOffer (managed BO) | Direct table access instead of READ ENTITY | Replace SELECT with READ ENTITIES or association-based read |
| R2 | ABAP | Duplicate field(readonly) line for Discount | Copy-paste error in BDEF | Remove duplicate line |
| R3 | ABAP/Fiori | Orphaned UI fields (AcceptOfferButton etc.) | Metadata ext references fields not in CDS | Add virtual fields to projection view OR use action projection |
| R4 | ABAP/Fiori | Orphaned criticality virtual fields | Same as R3 | Add virtual fields to projection view |
| R5 | Security | SELECT without auth check on personal data | validateSingleActiveOffer uses direct SELECT | Same fix as R1 — use READ ENTITIES |
| R6 | Security | String template in URL (injection) | validate_contract builds URL dynamically | Use query parameter encoding, not string template |
| R7 | Performance | SELECT inside LOOP (validateSingleActiveOffer) | Same as R1 | Same fix |
| R8 | Performance | SELECT SINGLE inside LOOP (determineApprovalRequired) | Threshold read per record | Read threshold once before loop |
| R9 | Adversarial | Threshold uses > not >= (design gap D3) | Business intent unclear | Confirm with business: > or >= |
| R10 | Adversarial | No DB CHECK constraint on discount_pct | Table DDL not in diff | Add CHECK (discount_pct BETWEEN 0 AND 30) to zret_offer |
| R11 | Adversarial | No block on modify while PENDING | validateApprovalStatus only on save, not modify | Add determination or validation on modify for PENDING status |

> **11 RED findings total. Circuit breaker stops pipeline.**
> Human must review findings, confirm design decisions (especially D3: > vs >=), and decide which fixes to apply before iteration 2.
