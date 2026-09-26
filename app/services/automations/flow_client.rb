# Chat<->Flow bridge, Chat side (12 Sep 2026).
#
# IMPORTANT - naming: this is deliberately never surfaced or referred to
# as "Flow" or "Connect to Flow" anywhere a business can see it. The
# Chat-facing feature name is "Automations". Businesses using it never
# become Flow customers, never see a Flow login, and never get anything
# beyond the scoped credits/workflow-trigger surface below - see
# services/chat_shadow.py on the synkra-core side for the full design.
#
# Two kinds of call:
#   - Internal (provision!, update_plan!): authenticated with
#     CHAT_SHARED_SECRET, a static value shared between this app and
#     synkra-core specifically (NOT the WEBHOOK_SECRET client-hub uses -
#     kept separate on purpose, see synkra-core/routers/chat_integration.py).
#   - Per-account (credits, consume_credit!, trigger_workflow!): authenticated
#     with this account's own SYN_... key (stored encrypted on
#     SynkraSubscription#flow_api_key).
class Automations::FlowClient
  BASE_URL = ENV.fetch('FLOW_API_BASE_URL', 'https://api.synkra.co.za')

  Result = Struct.new(:success?, :data, :error, keyword_init: true)

  def initialize(subscription = nil)
    @subscription = subscription
    @shared_secret = ENV.fetch('CHAT_SHARED_SECRET', nil)
  end

  def configured?
    @shared_secret.present?
  end

  # --- Internal, secret-authed ---

  def provision!(chat_account_id:, chat_plan:)
    return Result.new(success?: false, error: 'CHAT_SHARED_SECRET is not configured') unless configured?

    response = internal_connection.post('/internal/chat-accounts/provision') do |req|
      req.body = { chat_account_id: chat_account_id.to_s, chat_plan: chat_plan }
    end

    handle_response(response)
  end

  def update_plan!(chat_account_id:, chat_plan:)
    return Result.new(success?: false, error: 'CHAT_SHARED_SECRET is not configured') unless configured?

    response = internal_connection.post('/internal/chat-accounts/plan') do |req|
      req.body = { chat_account_id: chat_account_id.to_s, chat_plan: chat_plan }
    end

    handle_response(response)
  end

  # --- Internal, secret-authed: ops key management ---
  # No customer-facing equivalent exists on purpose - a business never
  # manages its own Automations key (see the module comment). These
  # exist for support/incident response (e.g. a key needs revoking) -
  # see lib/tasks/automations.rake.

  def add_key!(chat_account_id:)
    return Result.new(success?: false, error: 'CHAT_SHARED_SECRET is not configured') unless configured?

    response = internal_connection.post("/internal/chat-accounts/#{chat_account_id}/keys")
    handle_response(response)
  end

  def list_keys(chat_account_id:)
    return Result.new(success?: false, error: 'CHAT_SHARED_SECRET is not configured') unless configured?

    response = internal_connection.get("/internal/chat-accounts/#{chat_account_id}/keys")
    handle_response(response)
  end

  def revoke_key!(chat_account_id:, key_id:)
    return Result.new(success?: false, error: 'CHAT_SHARED_SECRET is not configured') unless configured?

    response = internal_connection.delete("/internal/chat-accounts/#{chat_account_id}/keys/#{key_id}")
    handle_response(response)
  end

  # --- Per-account, key-authed ---

  def credits
    return Result.new(success?: false, error: 'No Automations API key on this account') unless keyed?

    response = keyed_connection.get('/api/v1/credits')
    handle_response(response)
  end

  def consume_credit!(kind:, amount: 1)
    return Result.new(success?: false, error: 'No Automations API key on this account') unless keyed?

    response = keyed_connection.post('/api/v1/credits/consume') do |req|
      req.body = { kind: kind, amount: amount }
    end

    handle_response(response)
  end

  def trigger_workflow!(workflow_id, payload = {})
    return Result.new(success?: false, error: 'No Automations API key on this account') unless keyed?

    response = keyed_connection.post("/api/v1/workflows/#{workflow_id}/trigger") do |req|
      req.body = payload
    end

    handle_response(response)
  end

  private

  def keyed?
    @subscription&.flow_api_key.present?
  end

  def internal_connection
    @internal_connection ||= Faraday.new(url: BASE_URL) do |f|
      f.request :json
      f.response :json, content_type: /\bjson$/
      f.headers['X-Synkra-Secret'] = @shared_secret
      f.adapter Faraday.default_adapter
    end
  end

  def keyed_connection
    @keyed_connection ||= Faraday.new(url: BASE_URL) do |f|
      f.request :json
      f.response :json, content_type: /\bjson$/
      f.headers['Authorization'] = "Bearer #{@subscription.flow_api_key}"
      f.adapter Faraday.default_adapter
    end
  end

  def handle_response(response)
    body = response.body || {}
    if response.success?
      Result.new(success?: true, data: body)
    else
      Result.new(success?: false, error: body['detail'] || body['message'] || 'Automations request failed')
    end
  rescue StandardError => e
    Result.new(success?: false, error: e.message)
  end
end
