# Synkra Chat billing: talks to Paystack's REST API directly (no gem -
# Paystack's API is simple REST and a full SDK isn't warranted for the
# handful of endpoints we actually need). Requires PAYSTACK_SECRET_KEY
# to be set; every method returns a clear error rather than raising
# when that's missing, so a misconfigured environment fails safely
# rather than crashing billing pages.
class Billing::PaystackService
  BASE_URL = 'https://api.paystack.co'

  Result = Struct.new(:success?, :data, :error, keyword_init: true)

  def initialize
    @secret_key = ENV.fetch('PAYSTACK_SECRET_KEY', nil)
  end

  def configured?
    @secret_key.present?
  end

  # Starts a checkout. When plan_code is given, Paystack automatically
  # creates the recurring subscription once this initial transaction
  # succeeds. When it's nil, this is a genuine one-time charge (e.g. a
  # message add-on pack purchase - see Billing::MessageAddonPack) and
  # Paystack does not create any subscription. Either way, returns the
  # authorization_url to redirect the customer to.
  def initialize_transaction(email:, amount_zar:, callback_url:, plan_code: nil, metadata: {})
    return Result.new(success?: false, error: 'Paystack is not configured') unless configured?

    response = connection.post('/transaction/initialize') do |req|
      body = {
        email: email,
        amount: (amount_zar.to_f * 100).to_i, # Paystack expects the amount in cents
        callback_url: callback_url,
        metadata: metadata
      }
      body[:plan] = plan_code if plan_code.present?
      req.body = body
    end

    handle_response(response)
  end

  def verify_transaction(reference)
    return Result.new(success?: false, error: 'Paystack is not configured') unless configured?

    response = connection.get("/transaction/verify/#{reference}")
    handle_response(response)
  end

  # Charges a previously-captured card/direct-debit authorization
  # on-demand, outside the normal subscription billing cycle. Used for
  # extra seats (Billing::ExtraSeatsController) - seats aren't part of
  # the recurring plan amount, so they can't ride on Paystack's own
  # subscription billing the way the base plan price does. Requires an
  # authorization_code, which only exists after this account's first
  # successful plan payment (see PaystackWebhookHandler#capture_authorization) -
  # callers must check SynkraSubscription#paystack_authorization_code.present?
  # before calling this.
  def charge_authorization(email:, amount_zar:, authorization_code:, metadata: {})
    return Result.new(success?: false, error: 'Paystack is not configured') unless configured?

    response = connection.post('/transaction/charge_authorization') do |req|
      req.body = {
        email: email,
        amount: (amount_zar.to_f * 100).to_i,
        authorization_code: authorization_code,
        metadata: metadata
      }
    end

    handle_response(response)
  end

  def cancel_subscription(subscription_code:, email_token:)
    return Result.new(success?: false, error: 'Paystack is not configured') unless configured?

    response = connection.post('/subscription/disable') do |req|
      req.body = { code: subscription_code, token: email_token }
    end

    handle_response(response)
  end

  # Creates a subscription directly from a stored card/direct-debit
  # authorization (no checkout redirect). Used for plan switches on an
  # already-paying customer - per Paystack's own docs, start_date is
  # "useful... when you want to switch a customer to a different
  # plan": passing the next billing date defers the first charge on
  # the new plan to then, so this never double-charges someone who was
  # just billed moments ago for their old plan's final cycle.
  def create_subscription(customer_code:, plan_code:, authorization_code:, start_date: nil)
    return Result.new(success?: false, error: 'Paystack is not configured') unless configured?

    response = connection.post('/subscription') do |req|
      req.body = {
        customer: customer_code,
        plan: plan_code,
        authorization: authorization_code,
        start_date: start_date&.iso8601
      }.compact
    end

    handle_response(response)
  end

  # Verifies that a webhook actually came from Paystack, per their
  # documented signature scheme (HMAC-SHA512 of the raw body, using the
  # secret key). Never trust an unsigned/incorrectly-signed webhook.
  def self.verify_webhook_signature(raw_body, signature_header)
    secret_key = ENV.fetch('PAYSTACK_SECRET_KEY', nil)
    return false if secret_key.blank? || signature_header.blank?

    expected = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha512'), secret_key, raw_body)
    ActiveSupport::SecurityUtils.secure_compare(expected, signature_header)
  end

  private

  def connection
    @connection ||= Faraday.new(url: BASE_URL) do |f|
      f.request :json
      f.response :json, content_type: /\bjson$/
      f.headers['Authorization'] = "Bearer #{@secret_key}"
      f.adapter Faraday.default_adapter
    end
  end

  def handle_response(response)
    body = response.body || {}
    if response.success? && body['status']
      Result.new(success?: true, data: body['data'])
    else
      Result.new(success?: false, error: body['message'] || 'Paystack request failed')
    end
  rescue StandardError => e
    Result.new(success?: false, error: e.message)
  end
end
