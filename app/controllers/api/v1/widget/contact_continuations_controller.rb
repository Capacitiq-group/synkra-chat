# Synkra Chat identity layer. A visitor on a new device/browser who has
# chatted before can request a "continue my conversation" email. Unlike
# ContactVerificationsController, this does NOT require the requesting
# browser to already be authenticated as any particular contact - that's
# the whole point (it's a brand new session with no contact yet).
class Api::V1::Widget::ContactContinuationsController < Api::V1::Widget::BaseController
  # set_contact (from WebsiteTokenHelper) would normally require an
  # existing valid X-Auth-Token and 404 without one - but this endpoint
  # is specifically for a brand new browser/device with no contact yet,
  # so it must be skipped here.
  skip_before_action :set_contact, raise: false

  def create
    email = params[:email].to_s.strip.downcase

    contact_inbox = ContactInbox.joins(:contact).find_by(
      inbox_id: @web_widget.inbox.id,
      contacts: { email: email }
    )

    if contact_inbox.present?
      token = contact_inbox.contact.generate_identity_token(purpose: :continue_conversation)
      continuation_url = "#{root_url}widget/continue_conversation?token=#{token}&website_token=#{@web_widget.website_token}"
      ContactIdentityMailer.continue_conversation(contact: contact_inbox.contact, continuation_url: continuation_url).deliver_later
    end

    # Same response whether or not we found a match - never reveal
    # whether an email address exists in the system.
    render json: { message: 'If that email matches a previous conversation, we sent a link to continue it.' }
  end
end
