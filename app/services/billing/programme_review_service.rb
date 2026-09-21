# Manual review outcomes (super admin): approve, reject, or ask for more
# information. Emails the applicant's admins, and on approval moves an
# already-paying account onto the programme price.
class Billing::ProgrammeReviewService
  def initialize(verification, reviewer:)
    @verification = verification
    @reviewer = reviewer
  end

  def approve(note: nil)
    return false unless reviewable?

    @verification.approve!(reviewer: @reviewer, note: note)
    Billing::ProgrammePricingService.new(@verification.account).apply!
    notify('approved')
  end

  def reject(note:)
    return false unless reviewable? && note.to_s.strip.present?

    @verification.reject!(reviewer: @reviewer, note: note.to_s.strip)
    notify('rejected')
  end

  def request_info(note:)
    return false unless reviewable? && note.to_s.strip.present?

    @verification.request_info!(reviewer: @reviewer, note: note.to_s.strip)
    notify('needs_info')
  end

  private

  def reviewable?
    %w[review needs_info].include?(@verification.status)
  end

  def notify(outcome)
    Billing::ProgrammeMailer.review_outcome(verification: @verification, outcome: outcome).deliver_later
    true
  end
end
