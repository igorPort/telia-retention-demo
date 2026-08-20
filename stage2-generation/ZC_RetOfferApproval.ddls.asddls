" Artifact: ZC_RetOfferApproval (Projection CDS View — Child)
" Generated from: Domain Model v1 (approved)
@AccessControl.authorizationCheck: #CHECK_REQUIRED
@EndUserText.label: 'Retention Offer Approval'
@ObjectModel.writeActive: true
@Metadata.allowExtensions: true
define view entity ZC_RetOfferApproval
  as projection on ZI_RetOfferApproval as Approval
{
  key Approval.ApprovalUUID,
      Approval.ParentUUID,
      Approval.Approver,
      Approval.ApprovalTimestamp,
      Approval.Decision,
      Approval.Comment,
      _Parent : redirected ZI_RetentionOffer
}
