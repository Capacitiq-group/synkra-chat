# Super admin queue for Student document reviews and Community Access
# applications. Lists everything waiting for a person and lets the
# reviewer approve, reject or ask for more information (each with a note
# the applicant is emailed).
class SuperAdmin::ProgrammeReviewsController < SuperAdmin::ApplicationController
  before_action :set_verification, only: %i[show approve reject request_info]

  def index
    @waiting = SynkraProgrammeVerification.where(status: %w[review needs_info]).order(:submitted_at)
    @recent = SynkraProgrammeVerification.where(status: %w[verified rejected])
                                         .where.not(verification_method: 'email').order(reviewed_at: :desc).limit(20)
  end

  def show; end

  def approve
    outcome(service.approve(note: params[:note]), 'Approved. The applicant has been emailed.')
  end

  def reject
    outcome(service.reject(note: params[:note]), 'Rejected. The applicant has been emailed.')
  end

  def request_info
    outcome(service.request_info(note: params[:note]), 'More information requested. The applicant has been emailed.')
  end

  private

  def set_verification
    @verification = SynkraProgrammeVerification.find(params[:id])
  end

  def service
    Billing::ProgrammeReviewService.new(@verification, reviewer: current_super_admin.email)
  end

  def outcome(done, message)
    if done
      redirect_to super_admin_programme_reviews_path, notice: message
    else
      redirect_to super_admin_programme_review_path(@verification), alert: 'Could not save that decision. A note is required to reject or ask for more information.'
    end
  end
end
