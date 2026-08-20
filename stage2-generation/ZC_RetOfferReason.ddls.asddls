" Artifact: ZC_RetOfferReason (Projection CDS View — Child)
" Generated from: Domain Model v1 (approved)
@AccessControl.authorizationCheck: #CHECK_REQUIRED
@EndUserText.label: 'Retention Offer Reason'
@ObjectModel.writeActive: true
@Metadata.allowExtensions: true
define view entity ZC_RetOfferReason
  as projection on ZI_RetOfferReason as Reason
{
  key Reason.ReasonUUID,
      Reason.ParentUUID,
      Reason.ReasonCode,
      Reason.ReasonText,
      _Parent : redirected ZI_RetentionOffer
}
