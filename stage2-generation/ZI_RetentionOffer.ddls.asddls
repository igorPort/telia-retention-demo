" Artifact: ZI_RetentionOffer (Interface CDS View — Root Entity)
" Generated from: Domain Model v1 (approved)
" Invariants: 1, 2, 3, 4
" House rules: CDS-001 (no UI ann.), CDS-002 (label), CDS-003 (auth), CDS-004 (semanticKey), CDS-005 (no SELECT *), CDS-011 (key fields)
@AccessControl.authorizationCheck: #CHECK_REQUIRED
@EndUserText.label: 'Retention Offer'
@ObjectModel.modelPattern: #MANAGED
@ObjectModel.semanticKey: ['OfferUUID']
@ObjectModel.writeActive: true
@ObjectModel.lifecycle.responsible: 'RetentionOfferBO'
define root view entity ZI_RetentionOffer
  as select from zret_offer as Offer

  composition [0..*] of ZI_RetOfferReason  as _Reasons  on $projection.OfferUUID = _Reasons.ParentUUID
  composition [0..*] of ZI_RetOfferApproval as _Approvals on $projection.OfferUUID = _Approvals.ParentUUID

  association to ZI_Contract   as _Contract   on $projection.ContractUUID = _Contract.ContractUUID
  association to ZI_Customer   as _Customer   on $projection.CustomerUUID = _Customer.CustomerUUID
  association to ZI_Interaction as _InteractionHistory on $projection.CustomerUUID = _InteractionHistory.CustomerUUID
{
  key Offer.offer_uuid            as OfferUUID,
      Offer.contract_uuid         as ContractUUID,
      Offer.customer_uuid         as CustomerUUID,
      Offer.discount_pct          as Discount,
      Offer.offer_status          as OfferStatus,
      Offer.valid_from            as ValidFrom,
      Offer.valid_to              as ValidTo,
      Offer.approval_status       as ApprovalStatus,
      Offer.approval_threshold   as ApprovalThresholdAtCreation,
      Offer.arpu                  as ARPU,
      Offer.segment               as Segment,
      Offer.contract_lifetime     as ContractLifetime,
      Offer.last_changed_at       as LastChangedAt,
      Offer.last_changed_by       as LastChangedBy,
      Offer.created_at            as CreatedAt,
      Offer.created_by            as CreatedBy,

      _Reasons,
      _Approvals,
      _Contract,
      _Customer,
      _InteractionHistory
}
