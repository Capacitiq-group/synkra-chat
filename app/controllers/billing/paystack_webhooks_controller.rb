# Synkra Chat billing: receives Paystack's webhook calls. Deliberately
# NOT nested under Api::V1::Accounts::BaseController - Paystack calls
# this directly with no session/API token, only its own HMAC signature,
# which we verify before trusting anything in the payload.
class Billing::PaystackWebhooksController < ActionController::API
  # Idempotency: Paystack may retry a webhook delivery. We don't yet
  # persist a processed-event-id table (kept simple for V1), but every
  # handler in Billing::PaystackWebhookHandler is itself idempotent -
  # re-applying the same event twice just re-sets the same state,
  # rather than e.g. double-charging or double-notifying in a harmful
  # way. A dedicated dedup table is a reasonable future hardening step
  # if retries turn out to cause duplicate notification emails.
  def create
    raw_body = request.raw_post
    signature = request.headers['x-paystack-signature']

    unless Billing::PaystackService.verify_webhook_signature(raw_body, signature)
      Rails.logger.warn '[SynkraBilling] Rejected Paystack webhook with invalid signature'
      head :unauthorized
      return
    end

    event = JSON.parse(raw_body)
    Billing::PaystackWebhookHandler.new(event).process!
    head :ok
  rescue JSON::ParserError
    head :bad_request
  rescue StandardError => e
    Rails.logger.error "[SynkraBilling] Error processing Paystack webhook: #{e.message}"
    # Still return 200 so Paystack doesn't retry-storm us for an error
    # on our side that a retry wouldn't fix anyway - it's logged above
    # for us to investigate.
    head :ok
  end
end
