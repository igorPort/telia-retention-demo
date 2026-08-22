*&---------------------------------------------------------------------*
*& Report zrep_customers
*&---------------------------------------------------------------------*
REPORT zrep_customers.

DATA: lt_customers TYPE TABLE OF zi_customer,
      lo_alv       TYPE REF TO cl_salv_table.

START-OF-SELECTION.
  SELECT * FROM zi_customer INTO TABLE @lt_customers.

  IF sy-subrc = 0.
    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_customers
        ).

        " Basic ALV functions
        DATA(lo_functions) = lo_alv->get_functions( ).
        lo_functions->set_all( abap_true ).

        lo_alv->display( ).
      CATCH cx_salv_msg.
        MESSAGE 'Error creating ALV' TYPE 'E'.
    ENDTRY.
  ELSE.
    MESSAGE 'No customers found' TYPE 'I'.
  ENDIF.
