# Handles a Chat business's end-customer (Contact) clicking
# "unsubscribe" from that business's own marketing email. Distinct
# from MarketingUnsubscriptionsController (which is for Capacitiq's
# own marketing to Chat account users) - this is a different
# relationship: Capacitiq is providing the infrastructure here, the
# Chat BUSINESS is the actual sender/data controller. Token-based, no
# login required, same reasoning as
# ContactEmailVerificationsController.
class ContactMarketingUnsubscriptionsController < ActionController::Base
  layout false

  def show
    contact = Contact.find_signed(params[:token], purpose: :unsubscribe_marketing)

    if contact.nil?
      @status = :invalid
    else
      contact.update!(marketing_opt_in: false)
      @status = :unsubscribed
    end
  end
end
