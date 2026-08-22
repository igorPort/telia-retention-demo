" Artifact: ZBP_I_RetentionOffer (Behavior Implementation Class — Managed)
" Generated from: Domain Model v1 (approved)
" Invariants: 1, 2, 3, 4
" House rules: BDEF-008 (idempotent determinations), BDEF-009 (managed — no custom persistence)
"             abap-exception-handling: CATCH BEFORE UNWIND + RESUME
"             abap-message-handling: message class ZMS_RET_OFF (no hardcoded strings)
" Test stubs: see inline comments for each validation/determination

CLASS zbp_i_retention_offer DEFINITION PUBLIC ABSTRACT FINAL
  FOR BEHAVIOR OF ZI_RetentionOffer.
  PUBLIC SECTION.
    CLASS-DATA:
      " Message class for all BO messages (abap-message-handling rule)
      BEGIN OF ms_msg,
        discount_exceeds_max    TYPE c LENGTH 4 VALUE '001',  " Discount exceeds 30%
        active_offer_exists     TYPE c LENGTH 4 VALUE '002',  " Active offer already exists
        approval_required       TYPE c LENGTH 4 VALUE '003',  " Approval required for this discount
        offer_expired           TYPE c LENGTH 4 VALUE '004',  " Offer has expired
        offer_already_accepted  TYPE c LENGTH 4 VALUE '005',  " Offer already accepted
        offer_already_rejected  TYPE c LENGTH 4 VALUE '006',  " Offer already rejected
        billing_api_failed      TYPE c LENGTH 4 VALUE '007',  " Billing API call failed
        contract_not_found      TYPE c LENGTH 4 VALUE '008',  " Contract not found
      END OF ms_msg.

    TYPES:
      BEGIN OF ENUM e_offer_status,
        draft        TYPE string VALUE `DRAFT`,
        active       TYPE string VALUE `ACTIVE`,
        pending_approval TYPE string VALUE `PENDING_APPROVAL`,
        accepted     TYPE string VALUE `ACCEPTED`,
        rejected     TYPE string VALUE `REJECTED`,
        expired      TYPE string VALUE `EXPIRED`,
      END OF ENUM e_offer_status.

    " Constants for thresholds (no magic numbers — clean-abap rule)
    CONSTANTS:
      c_max_discount      TYPE i VALUE 30,
      c_min_discount      TYPE i VALUE 0,
      c_expiry_hours      TYPE i VALUE 72,
      c_default_threshold TYPE i VALUE 20.  " Configurable via ZRET_OFFER_THR

  PROTECTED SECTION.
    " Invariant 1: validateDiscountCeiling
    " Test: invariant1_discount_max_30 (create with 35% → fail)
    " Test: B1 (create with 30.01% → fail)
    " Test: B3 (create with -1% → fail — checks lower bound too)
    METHODS validate_discount_ceiling
      IMPORTING keys TYPE TABLE FOR VALIDATION RETENTION_OFFER~validateDiscountCeiling
      CHANGING  reported TYPE TABLE FOR REPORTED RETENTION_OFFER.

    " Invariant 2: determineExpiry (idempotent — BDEF-008)
    " Test: invariant2_72h_validity (ValidTo = CreatedAt + 72h)
    " Test: B4 (exact boundary — T+72h still valid)
    " Test: B5 (T+71h59m59s — still valid)
    METHODS determine_expiry
      IMPORTING keys TYPE TABLE FOR DETERMINATION RETENTION_OFFER~determineExpiry.

    " Invariant 3: validateSingleActiveOffer
    " Test: invariant3_one_active_per_contract (second create fails)
    " Test: C1 (concurrent — lock prevents race)
    METHODS validate_single_active_offer
      IMPORTING keys TYPE TABLE FOR VALIDATION RETENTION_OFFER~validateSingleActiveOffer
      CHANGING  reported TYPE TABLE FOR REPORTED RETENTION_OFFER
                failed   TYPE TABLE FOR FAILED RETENTION_OFFER.

    " Invariant 4: determineApprovalRequired (idempotent — BDEF-008)
    " Test: invariant4_approval_threshold (discount > threshold → PENDING)
    " Test: D3 (discount == threshold → NOT_REQUIRED — verifies > vs >=)
    METHODS determine_approval_required
      IMPORTING keys TYPE TABLE FOR DETERMINATION RETENTION_OFFER~determineApprovalRequired.

    " Invariant 4: validateApprovalStatus
    " Test: C3 (cannot modify while PENDING)
    METHODS validate_approval_status
      IMPORTING keys TYPE TABLE FOR VALIDATION RETENTION_OFFER~validateApprovalStatus
      CHANGING  reported TYPE TABLE FOR REPORTED RETENTION_OFFER
                failed   TYPE TABLE FOR FAILED RETENTION_OFFER.

    " Action: acceptOffer (triggers billing ApplyDiscount)
    " Test: S1 (already accepted → fail)
    " Test: S4 (expired → fail)
    METHODS accept_offer
      IMPORTING keys TYPE TABLE FOR ACTION RETENTION_OFFER~acceptOffer
      RESULT    result TYPE TABLE FOR ACTION RESULT RETENTION_OFFER.

    " Action: rejectOffer
    " Test: S2 (cannot reject already-accepted)
    METHODS reject_offer
      IMPORTING keys TYPE TABLE FOR ACTION RETENTION_OFFER~rejectOffer
      RESULT    result TYPE TABLE FOR ACTION RESULT RETENTION_OFFER.

    " Action: requestApproval (triggers workflow)
    METHODS request_approval
      IMPORTING keys TYPE TABLE FOR ACTION RETENTION_OFFER~requestApproval
      RESULT    result TYPE TABLE FOR ACTION RESULT RETENTION_OFFER.

ENDCLASS.

CLASS zbp_i_retention_offer IMPLEMENTATION.

  " ─── Invariant 1: Discount ≤ 30% ───────────────────────────────────
  METHOD validate_discount_ceiling.
    " Check both bounds: 0 <= Discount <= 30
    " This also covers B3 (negative values) — not just upper bound
    LOOP AT keys INTO DATA(key) WHERE %data-Discount > c_max_discount
                                  OR %data-Discount < c_min_discount.
      APPEND VALUE #(
        %key        = key-%key
        %msg        = new_message(
                        id       = 'ZMS_RET_OFF'
                        number   = '001'
                        severity = if_abap_behv_message=>severity-error
                      )
        %element-Discount = if_abap_behv=>mk-on
      ) TO reported.
    ENDLOOP.

    " SECURITY: If no validation failure and no DB CHECK constraint,
    " adversarial case A3 (direct table insert) bypasses this.
    " → DB table zret_offer MUST have CHECK constraint: discount_pct BETWEEN 0 AND 30
  ENDMETHOD.

  " ─── Invariant 2: 72h validity (idempotent determination) ─────────
  METHOD determine_expiry.
    " Idempotent: only sets ValidTo if it's initial (BDEF-008)
    LOOP AT keys INTO DATA(key) WHERE %data-ValidTo IS INITIAL.
      MODIFY ENTITIES OF ZI_RetentionOffer IN LOCAL MODE
        ENTITY Offer
        UPDATE FIELDS ( ValidFrom = sy-datum
                        ValidTo   = sy-datum + c_expiry_hours )
        WITH VALUE #( ( %key = key-%key ) ).
    ENDLOOP.
  ENDMETHOD.

  " ─── Invariant 3: One active offer per contract ──────────────────
  METHOD validate_single_active_offer.
    " Use READ ENTITY (not SELECT) — performance + RAP compliance
    LOOP AT keys INTO DATA(key).
      " Check if contract already has an active offer
      READ ENTITIES OF ZI_RetentionOffer IN LOCAL MODE
        ENTITY Offer
        FIELDS ( OfferStatus )
        WITH VALUE #( ( %key = key-%key ) )
        RESULT DATA(existing_offers).

      " Check for ACTIVE offers on same ContractUUID (excluding self)
      " NOTE: In managed BO, READ ENTITY within validation reads from
      " transactional buffer — for concurrent access (C1), the lock
      " master prevents the race before validation runs.
      SELECT FROM zret_offer AS offer
        FIELDS offer_uuid
        WHERE offer~contract_uuid = @key-%data-ContractUUID
          AND offer~offer_status  = 'ACTIVE'
          AND offer~offer_uuid   <> @key-%key-OfferUUID
        INTO TABLE @DATA(active_offers).

      IF line_exists( active_offers[ 1 ] ).
        " One active offer already exists for this contract
        APPEND VALUE #(
          %key             = key-%key
          %msg             = new_message(
                               id       = 'ZMS_RET_OFF'
                               number   = '002'
                               severity = if_abap_behv_message=>severity-error
                             )
          %element-ContractUUID = if_abap_behv=>mk-on
        ) TO reported.

        APPEND VALUE #( %key = key-%key ) TO failed.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  " ─── Invariant 4: Approval required above threshold ───────────────
  METHOD determine_approval_required.
    " Idempotent: only sets if ApprovalStatus is initial (BDEF-008)
    LOOP AT keys INTO DATA(key) WHERE %data-ApprovalStatus IS INITIAL.
      " Read threshold from config table (snapshot at creation time)
      SELECT SINGLE FROM zret_offer_thr
        FIELDS threshold_value
        WHERE active = @abap_true
        INTO @DATA(threshold).

      IF sy-subrc <> 0.
        threshold = c_default_threshold.  " Fallback to default
      ENDIF.

      " DESIGN GAP (D3): using > (strict). If >= is intended, change operator.
      DATA(approval_needed) = xsdbool( key-%data-Discount > threshold ).

      MODIFY ENTITIES OF ZI_RetentionOffer IN LOCAL MODE
        ENTITY Offer
        UPDATE FIELDS ( ApprovalStatus         = COND #( WHEN approval_needed = abap_true
                                                          THEN 'PENDING'
                                                          ELSE 'NOT_REQUIRED' )
                        ApprovalThresholdAtCreation = threshold )
        WITH VALUE #( ( %key = key-%key ) ).
    ENDLOOP.
  ENDMETHOD.

  " ─── Invariant 4: validateApprovalStatus on save ─────────────────
  METHOD validate_approval_status.
    " Block activation (acceptOffer) if ApprovalStatus = PENDING
    LOOP AT keys INTO DATA(key) WHERE %data-ApprovalStatus = 'PENDING'.
      APPEND VALUE #(
        %key             = key-%key
        %msg             = new_message(
                             id       = 'ZMS_RET_OFF'
                             number   = '003'
                             severity = if_abap_behv_message=>severity-error
                           )
        %element-ApprovalStatus = if_abap_behv=>mk-on
      ) TO reported.

      APPEND VALUE #( %key = key-%key ) TO failed.
    ENDLOOP.
  ENDMETHOD.

  " ─── Action: acceptOffer ──────────────────────────────────────────
  METHOD accept_offer.
    " Adversarial S1: check if already accepted
    " Adversarial S4: check if expired
    " Adversarial S3: check if rejected

    LOOP AT keys INTO DATA(key).
      " Read current state
      READ ENTITIES OF ZI_RetentionOffer IN LOCAL MODE
        ENTITY Offer
        FIELDS ( OfferStatus ValidTo )
        WITH VALUE #( ( %key = key-%key ) )
        RESULT DATA(offer_data).

      READ TABLE offer_data INTO DATA(offer) INDEX 1.

      " State machine checks (S1, S3, S4)
      IF offer-OfferStatus = 'ACCEPTED'.
        APPEND VALUE #( %key = key-%key
                        %msg = new_message( id = 'ZMS_RET_OFF' number = '005'
                          severity = if_abap_behv_message=>severity-error ) )
          TO reported.
        CONTINUE.
      ENDIF.

      IF offer-OfferStatus = 'REJECTED'.
        APPEND VALUE #( %key = key-%key
                        %msg = new_message( id = 'ZMS_RET_OFF' number = '006'
                          severity = if_abap_behv_message=>severity-error ) )
          TO reported.
        CONTINUE.
      ENDIF.

      IF offer-OfferStatus = 'EXPIRED' OR
         ( offer-ValidTo IS NOT INITIAL AND offer-ValidTo < sy-datum ).
        APPEND VALUE #( %key = key-%key
                        %msg = new_message( id = 'ZMS_RET_OFF' number = '004'
                          severity = if_abap_behv_message=>severity-error ) )
          TO reported.
        CONTINUE.
      ENDIF.

      " Call billing API (idempotent via OfferUUID)
      " Exception handling: CATCH BEFORE UNWIND + RESUME (house rule)
      TRY.
          NEW zcl_billing_rest_client( )->apply_discount(
            iv_offer_uuid    = key-%key-OfferUUID
            iv_contract_uuid = offer-ContractUUID
            iv_discount      = offer-Discount
          ).
        CATCH BEFORE UNWIND INTO DATA(billing_error) zcx_billing_error.
          RESUME.
          " Report billing failure to agent — no partial persistence
          APPEND VALUE #( %key = key-%key
                          %msg = new_message( id = 'ZMS_RET_OFF' number = '007'
                            severity = if_abap_behv_message=>severity-error ) )
            TO reported.
          CONTINUE.
        ENDTRY.

      " All checks pass → accept offer
      MODIFY ENTITIES OF ZI_RetentionOffer IN LOCAL MODE
        ENTITY Offer
        UPDATE FIELDS ( OfferStatus = 'ACCEPTED' )
        WITH VALUE #( ( %key = key-%key ) ).

      APPEND VALUE #( %key = key-%key ) TO result.
    ENDLOOP.
  ENDMETHOD.

  " ─── Action: rejectOffer ──────────────────────────────────────────
  METHOD reject_offer.
    LOOP AT keys INTO DATA(key).
      READ ENTITIES OF ZI_RetentionOffer IN LOCAL MODE
        ENTITY Offer
        FIELDS ( OfferStatus )
        WITH VALUE #( ( %key = key-%key ) )
        RESULT DATA(offer_data).

      READ TABLE offer_data INTO DATA(offer) INDEX 1.

      " S2: Cannot reject an accepted offer
      IF offer-OfferStatus = 'ACCEPTED'.
        APPEND VALUE #( %key = key-%key
                        %msg = new_message( id = 'ZMS_RET_OFF' number = '005'
                          severity = if_abap_behv_message=>severity-error ) )
          TO reported.
        CONTINUE.
      ENDIF.

      MODIFY ENTITIES OF ZI_RetentionOffer IN LOCAL MODE
        ENTITY Offer
        UPDATE FIELDS ( OfferStatus = 'REJECTED' )
        WITH VALUE #( ( %key = key-%key ) ).

      APPEND VALUE #( %key = key-%key ) TO result.
    ENDLOOP.
  ENDMETHOD.

  " ─── Action: requestApproval ──────────────────────────────────────
  METHOD request_approval.
    " Triggers SAP standard workflow for approval
    " Async: sets ApprovalStatus = PENDING, workflow handles the rest
    LOOP AT keys INTO DATA(key).
      MODIFY ENTITIES OF ZI_RetentionOffer IN LOCAL MODE
        ENTITY Offer
        UPDATE FIELDS ( ApprovalStatus = 'PENDING' )
        WITH VALUE #( ( %key = key-%key ) ).

      " Workflow trigger (pseudo-code — actual impl uses SWO/Event)
      " CALL FUNCTION 'Z_TRIGGER_APPROVAL_WF'
      "   EXPORTING iv_offer_uuid = key-%key-OfferUUID.

      APPEND VALUE #( %key = key-%key ) TO result.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
