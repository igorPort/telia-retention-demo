# RAP (RESTful ABAP Programming) Mechanism Review & Domain Model Description

This document reviews the RAP mechanisms used in the Telecom Retention Offer proof-of-concept project and describes the underlying domain model.

## Domain Model Description

The domain model represents a CRM Churn Retention Enhancement scenario for a Telecom company (Telia POC). It handles the lifecycle of a retention offer provided to a customer.

### Entities and Aggregates
- **RetentionOffer (Root)**: The central business object managed with draft capabilities to support CRM agent interactions. Key fields include `OfferUUID`, `ContractUUID`, `CustomerUUID`, `Discount`, `OfferStatus`, `ValidFrom`, `ValidTo`, and `ApprovalStatus`.
- **RetentionOfferReason (Child)**: Stores reasons associated with the offer (e.g., rejection reasons).
- **RetentionOfferApproval (Child)**: Stores approval routing details when an offer discount exceeds a configured threshold.

> **Note on Customer Entities (GDPR Boundary)**
> You will notice there are no `Customer` or `Contract` entities stored within this aggregate. This is intentional. The RetentionOffer BO never copies customer personal data into its own tables. All personal data is accessed via read-only CDS associations to external entities (e.g., `ZI_Customer`, `ZI_Contract`). This establishes a strict **GDPR boundary** and respects the Bounded Context architecture.

### Business Rules (Invariants)
The domain model enforces four primary business rules:
1. **Discount Limit**: The maximum allowable discount is 30%.
2. **Offer Validity**: Once created, an offer is valid for exactly 72 hours.
3. **Uniqueness**: A given contract can have only one active retention offer at any time.
4. **Approval Threshold**: If the discount exceeds a specific threshold, managerial approval is required.

## RAP Mechanisms Utilized

The system leverages the SAP RESTful Application Programming (RAP) model to enforce business logic and constraints directly within the behavior definition (BDEF) and its implementation class.

| Invariant | RAP Construct | Enforcement Point | Details |
| :--- | :--- | :--- | :--- |
| **Discount Limit (≤ 30%)** | Validation | `on save` | Validation `validateDiscountCeiling` ensures the discount does not exceed 30% when the entity is saved. |
| **72h Validity** | Determination + Application Job | `on modify { create; }` | Determination `determineExpiry` calculates `ValidTo` (CreatedAt + 72h) upon creation. A background job later sweeps and expires them. |
| **One active offer per contract** | Validation + Lock | `on save` + `lock master` | Validation `validateSingleActiveOffer` queries active offers via `READ ENTITY` during save. Concurrency is handled via `lock master total etag LastChangedAt` with the scope defined by `ContractUUID`. |
| **Approval Threshold** | Determination + Action + Validation | `on modify` + `action` + `on save` | Determination `determineApprovalRequired` sets the status to PENDING if the discount is high. Action `requestApproval` calls the workflow. Validation `validateApprovalStatus` on save prevents activation while pending. |

### Additional RAP Features
- **Managed Implementation with Draft**: Enables optimistic concurrency, state persistence during UI interaction (Fiori Elements), and seamless resume/discard functionality (`with draft`).
- **Authorization Master**: `authorization master ( instance ) auth object Z_RET_OFF` ensures that only authorized CRM agents can create or modify offers.
- **Strict Mode**: Enforces newer, rigorous BDEF syntax and behaviors (`strict mode (2)`).
- **Draft Actions**: Supports standard draft operations: `edit`, `activate`, and `discard`.
- **Actions with Results**: Custom actions like `acceptOffer`, `rejectOffer`, and `requestApproval` return `$self` references as specified by house rules.
- **Field Controls**: Certain fields (e.g., `Discount`, `ContractUUID`) are marked as `readonly` conditionally after creation or specific transitions to prevent data tampering.
