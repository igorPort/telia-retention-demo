*&---------------------------------------------------------------------*
*& Report zrep_retention_offers
*&---------------------------------------------------------------------*
REPORT zrep_retention_offers.

DATA: lt_offers TYPE TABLE OF zi_retentionoffer,
      lo_alv    TYPE REF TO cl_salv_table.

START-OF-SELECTION.
  SELECT * FROM zi_retentionoffer INTO TABLE @lt_offers.

  IF sy-subrc = 0.
    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_offers
        ).

        " Basic ALV functions
        DATA(lo_functions) = lo_alv->get_functions( ).
        lo_functions->set_all( abap_true ).

        lo_alv->display( ).
      CATCH cx_salv_msg.
        MESSAGE 'Error creating ALV' TYPE 'E'.
    ENDTRY.
  ELSE.
    MESSAGE 'No retention offers found' TYPE 'I'.
  ENDIF.
