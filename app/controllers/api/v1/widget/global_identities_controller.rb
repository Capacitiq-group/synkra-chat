# Synkra Chat global identity layer.
#
# Establishes (or recognises) a person's identity ONCE, then links it to
# a business-specific Contact for whichever inbox they're currently
# talking to - rather than treating every business as a totally separate
# person. See SynkraGlobalUser for what does/doesn't live at this level.
class Api::V1::Widget::GlobalIdentitiesController < Api::V1::Widget::BaseController
  include TrustedDeviceHelper

  # This runs before any per-account contact/token exists yet - the
  # whole point of this controller is to establish that.
  skip_before_action :set_contact, raise: false

  # POST /api/v1/widget/global_identity
  # Given an email, either recognises an already-trusted device (no OTP
  # needed) or sends a fresh OTP and asks the frontend to collect it.
  def create
    email = params[:email].to_s.strip.downcase
    if email.blank?
      render_invalid_email
      return
    end

    trusted = trusted_global_user
    if trusted && trusted.email == email
      render json: { otp_required: false }.merge(finalize_identity_for_business(trusted))
      return
    end

    global_user = SynkraGlobalUser.find_or_initialize_by_email(email)
    global_user.save! if global_user.new_record?
    global_user.generate_and_send_otp!

    render json: { otp_required: true }
  end

  # POST /api/v1/widget/global_identity/verify_otp
  def verify_otp
    email = params[:email].to_s.strip.downcase
    global_user = SynkraGlobalUser.find_or_initialize_by_email(email)

    if global_user.new_record? || !global_user.verify_otp(params[:otp])
      render json: { verified: false, error: 'Incorrect or expired code' }, status: :unprocessable_entity
      return
    end

    set_trusted_device_cookie(global_user)
    render json: { verified: true }.merge(finalize_identity_for_business(global_user))
  end

  private

  def render_invalid_email
    render json: { error: 'A valid email is required' }, status: :unprocessable_entity
  end

  # Ensures a Contact exists for THIS business (account) for the given
  # global identity, links the two together, and returns the same kind
  # of session token Chatwoot's normal widget auth already uses - so
  # the frontend can proceed exactly as if this were a regular
  # pre-chat-form submission.
  def finalize_identity_for_business(global_user)
    contact_inbox = ContactInboxWithContactBuilder.new(
      inbox: @web_widget.inbox,
      contact_attributes: { email: global_user.email }
    ).perform
    contact = contact_inbox.contact

    if contact.synkra_global_user_id != global_user.id
      contact.update!(synkra_global_user_id: global_user.id)
    end
    if global_user.email_verified? && contact.email_verified_at.blank?
      contact.update!(email_verified_at: Time.current)
    end

    session_token = ::Widget::TokenService.new(
      payload: { source_id: contact_inbox.source_id, inbox_id: @web_widget.inbox.id }
    ).generate_token

    { contact_id: contact.id, source_id: contact_inbox.source_id, auth_token: session_token }
  end
end
