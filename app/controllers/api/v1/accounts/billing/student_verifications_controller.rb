# Synkra Student Programme: verify student status by institutional
# email + one-time code. Admin-only like the rest of billing (enforced
# by SynkraSubscriptionPolicy), since a verified status changes what
# the account is charged.
class Api::V1::Accounts::Billing::StudentVerificationsController < Api::V1::Accounts::BaseController
  before_action -> { check_authorization(SynkraSubscription) }

  ERROR_MESSAGES = {
    invalid_extension: 'Please pick one of the listed email endings.',
    invalid_local_part: 'That student number or username does not look valid.',
    invalid_institution: 'That institution name does not look valid.',
    institution_includes_extension: 'Enter only the institution name - pick the ending from the list.',
    already_verified: 'Your student status is already verified.',
    email_in_use: 'That student email is already linked to another Synkra account.',
    cooldown: 'Please wait a moment before requesting another code.',
    rate_limited: 'Too many codes requested. Please try again in an hour.',
    delivery_failed: "We couldn't send the code. Please try again shortly.",
    invalid_code: 'That code is not correct.',
    code_expired: 'That code has expired. Request a new one.',
    too_many_attempts: 'Too many incorrect attempts. Request a new code.',
    no_pending: 'Request a code first.'
  }.freeze

  RATE_LIMIT_CODES = %i[cooldown rate_limited].freeze

  def show
    render json: status_payload
  end

  def create
    result = service.send_code(
      local_part: params[:local_part],
      institution: params[:institution],
      extension: params[:extension]
    )
    return render_failure(result) unless result.success?

    render json: status_payload
  end

  def confirm
    result = service.confirm(code: params[:code])
    return render_failure(result) unless result.success?

    render json: status_payload
  end

  private

  def service
    ::Billing::StudentVerificationService.new(account: Current.account, user: Current.user)
  end

  def render_failure(result)
    status = RATE_LIMIT_CODES.include?(result.code) ? :too_many_requests : :unprocessable_entity
    render json: { error: ERROR_MESSAGES.fetch(result.code, 'Something went wrong.'), code: result.code }.merge(result.data.to_h),
           status: status
  end

  def status_payload
    active = SynkraProgrammeVerification.active_verification_for(Current.account.id, 'student')
    pending = SynkraProgrammeVerification.pending_for(Current.account.id, 'student')
    pending = nil if pending&.otp_expires_at.present? && pending.otp_expires_at < Time.current

    {
      programme: 'student',
      extensions: SynkraProgrammeVerification::STUDENT_EMAIL_EXTENSIONS,
      otp_length: SynkraProgrammeVerification::OTP_LENGTH,
      verified: active.present?,
      verified_email: active&.institution_email,
      expires_at: active&.expires_at,
      pending_email: pending&.institution_email,
      resend_available_at: pending&.otp_sent_at && (pending.otp_sent_at + SynkraProgrammeVerification::OTP_RESEND_COOLDOWN)
    }
  end
end
