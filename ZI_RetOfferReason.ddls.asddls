" Artifact: ZI_RetOfferReason (Interface CDS View — Child Entity)
" Generated from: Domain Model v1 (approved)
" Invariants: (child of root — inherits aggregate consistency)
" House rules: CDS-001, CDS-002, CDS-003, CDS-005, CDS-011
@AccessControl.authorizationCheck: #CHECK_REQUIRED
@EndUserText.label: 'Retention Offer Reason'
@ObjectModel.writeActive: true
define view entity ZI_RetOfferReason
  as select from zret_offer_reason as Reason
  association to ZI_RetentionOffer as _Parent on $projection.ParentUUID = _Parent.OfferUUID
{
  key Reason.reason_uuid    as ReasonUUID,
      Reason.parent_uuid    as ParentUUID,
      Reason.reason_code    as ReasonCode,
      Reason.reason_text    as ReasonText,
      _Parent
}
