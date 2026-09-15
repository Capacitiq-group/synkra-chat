# Synkra Chat global identity layer.
#
# Establishes (or recognises) a person's identity and links it to
# whatever business-specific Contact this browser is ALREADY chatting
# as - rather than treating every business as a totally separate
# person. This is deliberately a background/non-blocking step: it runs
# after a conversation already exists (same principle as the soft
# email-verification nudge), never before or instead of one. See
# SynkraGlobalUser for what does/doesn't live at the global level.
class Api::V1::Widget::GlobalIdentitiesController < Api::V1::Widget::BaseController
  include TrustedDeviceHelper

  # POST /api/v1/widget/global_identity
  # Given an email, either recognises an already-trusted device (no OTP
  # needed - link immediately) or sends a fresh OTP and asks the
  # frontend to collect it.
  def create
    email = params[:email].to_s.strip.downcase
    if email.blank?
      render_invalid_email
      return
    end

    trusted = trusted_global_user
    if trusted && trusted.email == email
      link_contact_to_global_user(trusted)
      render json: { otp_required: false, linked: true }
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
    link_contact_to_global_user(global_user)
    render json: { verified: true, linked: true }
  end

  private

  def render_invalid_email
    render json: { error: 'A valid email is required' }, status: :unprocessable_entity
  end

  # Links the contact THIS BROWSER IS ALREADY CHATTING AS (identified
  # the normal way, via the base controller's set_contact) to the given
  # global identity. Deliberately does not create or look up any other
  # contact/contact_inbox - this only ever touches @contact, so it can
  # never accidentally merge or duplicate a different conversation.
  def link_contact_to_global_user(global_user)
    return if @contact.blank?

    @contact.update!(synkra_global_user_id: global_user.id) if @contact.synkra_global_user_id != global_user.id
    if global_user.email_verified? && @contact.email_verified_at.blank?
      @contact.update!(email_verified_at: Time.current)
    end
  end
end
