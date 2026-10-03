# Super admin view of email inboxes whose mailbox provider has sent a
# forwarding verification email but the customer hasn't completed the
# confirmation yet. Synkra staff use this as a support tool: if a
# customer is stuck, staff can see which inbox is pending, open the
# corresponding conversation, and walk the customer through the last
# step. Read-only by design - no approve/reject - because the actual
# verification happens on the customer's side (Google/Microsoft), not
# ours.
class SuperAdmin::EmailVerificationReviewsController < SuperAdmin::ApplicationController
  def index
    @pending = Channel::Email
               .where.not(forwarding_verification_pending_at: nil)
               .where(forwarding_verification_completed_at: nil)
               .includes(:account)
               .order(forwarding_verification_pending_at: :asc)
  end
end
