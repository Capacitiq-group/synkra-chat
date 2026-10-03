# Synkra Chat identity layer. Handles a customer clicking the
# verification link from their email - a plain browser navigation,
# not a widget API call. Renders a simple standalone confirmation
# page rather than JSON.
class ContactEmailVerificationsController < ActionController::Base
  layout false

  def show
    contact = Contact.find_signed(params[:token], purpose: :verify_email)

    if contact.nil?
      @status = :invalid
    else
      contact.update!(email_verified_at: Time.current)
      @status = :verified
      @contact = contact
    end
  end
end
