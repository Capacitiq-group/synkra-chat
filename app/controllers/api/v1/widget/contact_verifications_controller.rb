# Synkra Chat identity layer. Called by the widget frontend right after
# the pre-chat form is submitted with an email address, to kick off
# email verification. Does not itself confirm anything - clicking the
# link in the resulting email is what actually verifies the contact
# (see ContactEmailVerificationsController).
class Api::V1::Widget::ContactVerificationsController < Api::V1::Widget::BaseController
  def create
    if @contact.email.blank?
      render json: { error: 'Contact has no email address to verify' }, status: :unprocessable_entity
      return
    end

    if @contact.email_verified?
      render json: { verified: true }
      return
    end

    token = @contact.generate_identity_token(purpose: :verify_email)
    verification_url = "#{root_url}widget/verify_email?token=#{token}"

    ContactIdentityMailer.verify_email(contact: @contact, verification_url: verification_url).deliver_later

    render json: { verified: false, message: 'Verification email sent' }
  end
end
