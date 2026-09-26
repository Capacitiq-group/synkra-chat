# Synkra Community Access Programme: application, status, and adding
# information when a reviewer asks for it. Admin-only like the rest of
# billing (SynkraSubscriptionPolicy).
class Api::V1::Accounts::Billing::CommunityApplicationsController < Api::V1::Accounts::BaseController
  before_action -> { check_authorization(SynkraSubscription) }

  ERROR_MESSAGES = {
    missing_fields: 'Please complete all required fields.',
    declaration_required: 'Please confirm the evidence declaration.',
    evidence_required: 'Please add at least one piece of evidence.',
    faith_photo_required: 'Faith-based organisations must include photos of the community initiative.',
    already_verified: 'Your organisation already has Community Access.',
    already_submitted: 'Your application is already being reviewed.',
    rate_limited: 'Too many applications submitted today. Please try again tomorrow.',
    too_many_files: 'Please upload no more than 10 files.',
    invalid_file_type: 'Evidence must be PDF, JPG, PNG or WebP files.',
    file_too_large: 'Each file must be 10 MB or smaller.',
    nothing_to_update: 'There is no application waiting for more information.',
    invalid_code: 'That reference code is not valid or has expired.',
    already_has_programme: 'Your account already has a discount programme active.',
    email_mismatch: "This code belongs to a different email address than your Synkra account's. Log in with the account whose email matches the application, or contact us at hello@synkra.co.za."
  }.freeze

  def show
    render json: status_payload
  end

  def create
    result = service.submit(fields: params, files: Array(params[:documents]))
    return render_failure(result) unless result.success?

    render json: status_payload
  end

  # Answering a reviewer's request for more information.
  def update
    result = service.add_information(message: params[:message], files: Array(params[:documents]))
    return render_failure(result) unless result.success?

    render json: status_payload
  end

  # Attaches an approved public application (from /community-access,
  # no login required to apply) to this now-existing account.
  def claim
    result = ::Billing::CommunityApplicationService.claim(access_token: params[:access_token], account: Current.account, user: Current.user)
    return render_failure(result) unless result.success?

    render json: status_payload
  end

  private

  def service
    ::Billing::CommunityApplicationService.new(account: Current.account, user: Current.user)
  end

  def render_failure(result)
    render json: { error: ERROR_MESSAGES.fetch(result.code, 'Something went wrong.'), code: result.code }.merge(result.data.to_h),
           status: :unprocessable_entity
  end

  def status_payload
    account_id = Current.account.id
    active = SynkraProgrammeVerification.active_verification_for(account_id, 'community')
    review = SynkraProgrammeVerification.open_review_for(account_id, 'community')
    latest = SynkraProgrammeVerification.for_programme('community').where(account_id: account_id).order(created_at: :desc).first
    rejection = latest if latest&.status == 'rejected'

    {
      programme: 'community',
      discounted_prices: SynkraPlan.programme_prices('community'),
      verified: active.present?,
      expires_at: active&.expires_at,
      review: review && { status: review.status, submitted_at: review.submitted_at, note: review.status == 'needs_info' ? review.review_note : nil },
      rejection: rejection && { note: rejection.review_note, reviewed_at: rejection.reviewed_at }
    }
  end
end
