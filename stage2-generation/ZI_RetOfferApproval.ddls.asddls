" Artifact: ZI_RetOfferApproval (Interface CDS View — Child Entity)
" Generated from: Domain Model v1 (approved)
" Invariants: 4 (approval threshold — this entity stores approval decisions)
" House rules: CDS-001, CDS-002, CDS-003, CDS-005, CDS-011
@AccessControl.authorizationCheck: #CHECK_REQUIRED
@EndUserText.label: 'Retention Offer Approval'
@ObjectModel.writeActive: true
define view entity ZI_RetOfferApproval
  as select from zret_offer_approval as Approval
  association to ZI_RetentionOffer as _Parent on $projection.ParentUUID = _Parent.OfferUUID
{
  key Approval.approval_uuid   as ApprovalUUID,
      Approval.parent_uuid     as ParentUUID,
      Approval.approver         as Approver,
      Approval.approval_ts      as ApprovalTimestamp,
      Approval.decision         as Decision,
      Approval.comment_text     as Comment,
      _Parent
}
