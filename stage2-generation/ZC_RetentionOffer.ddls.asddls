" Artifact: ZC_RetentionOffer (Projection CDS View — Root)
" Generated from: Domain Model v1 (approved)
" House rules: CDS-009 (redirect via $projection)
@AccessControl.authorizationCheck: #CHECK_REQUIRED
@EndUserText.label: 'Retention Offer'
@ObjectModel.writeActive: true
@Metadata.allowExtensions: true
define root view entity ZC_RetentionOffer
  as projection on ZI_RetentionOffer as Offer
{
  key Offer.OfferUUID,
      Offer.ContractUUID,
      Offer.CustomerUUID,
      Offer.Discount,
      Offer.OfferStatus,
      Offer.ValidFrom,
      Offer.ValidTo,
      Offer.ApprovalStatus,
      Offer.ApprovalThresholdAtCreation,
      Offer.ARPU,
      Offer.Segment,
      Offer.ContractLifetime,
      Offer.LastChangedAt,
      Offer.LastChangedBy,
      Offer.CreatedAt,
      Offer.CreatedBy,

      /* Compositions */
      _Reasons : redirected ZI_RetOfferReason,
      _Approvals : redirected ZI_RetOfferApproval,

      /* Associations */
      _Contract,
      _Customer,
      _InteractionHistory
}
