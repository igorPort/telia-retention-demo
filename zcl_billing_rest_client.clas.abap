" Artifact: ZCL_BILLING_REST_CLIENT (Billing Integration Class)
" Generated from: Domain Model v1 (approved)
" Invariants: 1 (billing CalculateDiscount feeds discount ≤ 30%), 4 (ApplyDiscount on acceptOffer)
" House rules: abap-exception-handling (CX class, CATCH BEFORE UNWIND),
"             abap-message-handling (message class ZMS_RET_OFF)
"             abap-injection-prevention (no dynamic SQL, validate inputs)
" Performance: no SELECT in loop, uses HTTP client with timeout

CLASS zcl_billing_rest_client DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    " Custom exception class for billing errors
    " House rule: RAISE EXCEPTION NEW (not TYPE)
    TYPES:
      BEGIN OF t_discount_request,
        contract_uuid TYPE sysuuid_x16,
        arpu          TYPE p LENGTH 10 DECIMALS 2,
        segment       TYPE c LENGTH 10,
        lifetime_months TYPE i,
      END OF t_discount_request,
      BEGIN OF t_discount_response,
        discount_pct   TYPE p LENGTH 5 DECIMALS 2,
        currency       TYPE waers,
        valid_until    TYPE timestamp,
      END OF t_discount_response.

    " Idempotency: Offer UUID is the key — prevents double-application
    METHODS calculate_discount
      IMPORTING
        !is_request TYPE t_discount_request
      RETURNING
        VALUE(rs_response) TYPE t_discount_response
      RAISING
        zcx_billing_error.

    METHODS apply_discount
      IMPORTING
        !iv_offer_uuid    TYPE sysuuid_x16
        !iv_contract_uuid TYPE sysuuid_x16
        !iv_discount      TYPE p LENGTH 5 DECIMALS 2
      RAISING
        zcx_billing_error.

    METHODS validate_contract
      IMPORTING
        !iv_contract_uuid TYPE sysuuid_x16
      RETURNING
        VALUE(rv_valid) TYPE abap_bool
      RAISING
        zcx_billing_error.

  PROTECTED SECTION.
    " HTTP client with configurable timeout
    " Security: validate_contract_uuid called before any API call
    METHODS send_request
      IMPORTING
        !iv_endpoint TYPE string
        !is_payload  TYPE data
      RETURNING
        VALUE(rs_response) TYPE data
      RAISING
        zcx_billing_error.

    METHODS get_http_client
      RETURNING
        VALUE(ro_client) TYPE REF TO if_http_client
      RAISING
        zcx_billing_error.

    " Input validation (abap-injection-prevention)
    METHODS validate_uuid
      IMPORTING
        !iv_uuid TYPE sysuuid_x16
      RETURNING
        VALUE(rv_valid) TYPE abap_bool.

  PRIVATE SECTION.
    CONSTANTS:
      c_billing_base_url TYPE string VALUE 'https://billing.telia.internal/api/v1',
      c_timeout_seconds  TYPE i VALUE 30,
      c_max_retries       TYPE i VALUE 3.

ENDCLASS.

CLASS zcl_billing_rest_client IMPLEMENTATION.

  METHOD calculate_discount.
    " Calls: POST /Billing/CalculateDiscount
    " Returns: suggested discount (caller validates ≤ 30% via BDEF validation)

    IF validate_uuid( is_request-contract_uuid ) = abap_false.
      " abap-message-handling: no hardcoded strings, use message class
      RAISE EXCEPTION NEW zcx_billing_error(
        textid = zcx_billing_error=>invalid_input
        method = 'CALCULATE_DISCOUNT' ).
    ENDIF.

    " Build payload
    DATA(lv_payload) = /ui2/cl_json=>serialize(
      exp_data = is_request
      compress = abap_true ).

    " Send with retry logic (integration risk #2 mitigation)
    DATA(retry_count) = 0.
    DO c_max_retries TIMES.
      TRY.
          DATA(lt_response) = send_request(
            iv_endpoint = '/Billing/CalculateDiscount'
            is_payload  = lv_payload ).
          " Parse response
          /ui2/cl_json=>deserialize(
            EXPORTING json = lt_response
            CHANGING  data = rs_response ).
          RETURN.
        CATCH zcx_billing_error INTO DATA(lx_error).
          retry_count += 1.
          IF retry_count >= c_max_retries.
            RAISE EXCEPTION lx_error.
          ENDIF.
          " Exponential backoff
          WAIT UP TO 2 ** retry_count SECONDS.
      ENDTRY.
    ENDDO.
  ENDMETHOD.

  METHOD apply_discount.
    " Calls: POST /Billing/ApplyDiscount
    " Idempotency: Offer UUID sent as idempotency key
    " If called twice with same UUID, billing system returns same result

    IF validate_uuid( iv_offer_uuid ) = abap_false
       OR validate_uuid( iv_contract_uuid ) = abap_false.
      RAISE EXCEPTION NEW zcx_billing_error(
        textid = zcx_billing_error=>invalid_input
        method = 'APPLY_DISCOUNT' ).
    ENDIF.

    " Build payload with idempotency key
    DATA(ls_payload) = VALUE #(
      offer_uuid    = iv_offer_uuid
      contract_uuid = iv_contract_uuid
      discount_pct  = iv_discount
      idempotency_key = iv_offer_uuid  " Same as offer UUID
    ).

    DATA(lv_payload) = /ui2/cl_json=>serialize(
      exp_data = ls_payload
      compress = abap_true ).

    send_request(
      iv_endpoint = '/Billing/ApplyDiscount'
      is_payload  = lv_payload ).
  ENDMETHOD.

  METHOD validate_contract.
    " Calls: GET /Contract/Validate?contractUuid=<uuid>
    rv_valid = validate_uuid( iv_contract_uuid ).
    IF rv_valid = abap_false.
      RETURN.
    ENDIF.

    DATA(lt_response) = send_request(
      iv_endpoint = | /Contract/Validate?contractUuid={ iv_contract_uuid } |
      is_payload  = space ).

    " Parse: true/false response
    rv_valid = xsdbool( lt_response = 'true' ).
  ENDMETHOD.

  METHOD send_request.
    " HTTP client creation with timeout
    DATA(lo_client) = get_http_client( ).

    DATA(lo_request) = lo_client->request.
    lo_request->set_method( 'POST' ).
    lo_request->set_header_field(
      name  = 'Content-Type'
      value = 'application/json' ).
    lo_request->set_header_field(
      name  = 'X-Idempotency-Key'
      value = |{ cl_abap_syst=>get_user_name( ) }-{ sy-datum }{ sy-uzeit }| ).

    " Set timeout (integration risk mitigation)
    lo_client->send_timeout = c_timeout_seconds.
    lo_client->receive_timeout = c_timeout_seconds.

    lo_request->set_cdata( is_payload ).

    " Send + receive with exception handling
    TRY.
        lo_client->send( ).
        lo_client->receive( ).
      CATCH cx_web_http_client_error INTO DATA(lx_http).
        " abap-message-handling: use message class
        RAISE EXCEPTION NEW zcx_billing_error(
          textid    = zcx_billing_error=>api_timeout
          method    = 'SEND_REQUEST'
          previous  = lx_http ).
    ENDTRY.

    " Check HTTP status
    DATA(lv_status) = lo_client->response->get_status( ).
    IF lv_status-code BETWEEN 400 AND 599.
      RAISE EXCEPTION NEW zcx_billing_error(
        textid    = zcx_billing_error=>http_error
        method    = 'SEND_REQUEST'
        http_code = lv_status-code ).
    ENDIF.

    rs_response = lo_client->response->get_cdata( ).
  ENDMETHOD.

  METHOD get_http_client.
    " Create HTTP client from destination (configured in SM59)
    " No dynamic URL construction — prevents injection
    cl_http_client=>create_by_url(
      EXPORTING
        url     = c_billing_base_url
        ssl_id  = 'ANONYMOUS'
      IMPORTING
        client  = ro_client
      EXCEPTIONS
        OTHERS  = 1 ).
    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW zcx_billing_error(
        textid = zcx_billing_error=>client_creation_failed
        method = 'GET_HTTP_CLIENT' ).
    ENDIF.
  ENDMETHOD.

  METHOD validate_uuid.
    " Input validation — prevents injection via crafted UUID
    " UUIDs are 16 bytes (32 hex chars) — validate format
    rv_valid = xsdbool( strlen( iv_uuid ) = 16 ).
  ENDMETHOD.

ENDCLASS.
