# Synkra Chat identity layer. Handles a customer clicking the
# "continue my conversation" link from their email on a new device.
# Verifies the signed token, then redirects into the actual widget
# page using Chatwoot's own existing widget session mechanism
# (Widget::TokenService + cw_conversation param) - not a new auth
# system, just reusing the one that already exists.
class ContactContinuationsController < ActionController::Base
  layout false

  def show
    website_token = params[:website_token]
    web_widget = Channel::WebWidget.find_by(website_token: website_token)
    contact = web_widget && Contact.find_signed(params[:token], purpose: :continue_conversation)

    if contact.nil? || web_widget.nil?
      @status = :invalid
      return
    end

    contact_inbox = ContactInbox.find_by(inbox_id: web_widget.inbox.id, contact_id: contact.id)

    if contact_inbox.nil?
      @status = :invalid
      return
    end

    session_token = ::Widget::TokenService.new(
      payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }
    ).generate_token

    redirect_to "/widget?website_token=#{website_token}&cw_conversation=#{session_token}"
  end
end
