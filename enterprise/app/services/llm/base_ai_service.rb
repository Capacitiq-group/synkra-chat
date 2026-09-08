# frozen_string_literal: true

# Base service for LLM operations using RubyLLM.
# New features should inherit from this class.
class Llm::BaseAiService
  DEFAULT_MODEL = Llm::Config::DEFAULT_MODEL
  DEFAULT_TEMPERATURE = 1.0

  attr_reader :model, :temperature

  def initialize(feature: nil, account: nil, fallback_model: nil)
    @llm_feature = feature
    @llm_account = account
    @fallback_model = fallback_model

    Llm::Config.initialize!
    setup_model
    setup_temperature
  end

  def chat(model: @model, temperature: @temperature)
    build_chat(model).with_temperature(temperature)
  end

  private

  # RubyLLM validates `model` against its own bundled model registry
  # before making any request. That's fine for real OpenAI/Anthropic
  # models, but a self-hosted model name (e.g. an Ollama tag like
  # "qwen2.5:7b-instruct-q4_K_M", reached via our own
  # CAPTAIN_OPEN_AI_ENDPOINT override) will never be in that registry.
  # Only fall back to assume_model_exists when the normal lookup
  # genuinely fails, so every already-working model path (real OpenAI/
  # Anthropic models via the real API) is completely unaffected.
  def build_chat(model)
    RubyLLM.chat(model: model)
  rescue RubyLLM::ModelNotFoundError
    RubyLLM.chat(model: model, provider: :openai, assume_model_exists: true)
  end

  # Strips markdown code fences (```json ... ``` or ``` ... ```) that some
  # LLM providers/gateways wrap around JSON responses despite response_format hints.
  def sanitize_json_response(response)
    return response if response.nil?

    response.strip.sub(/\A```(?:\w*)\s*\n?/, '').sub(/\n?\s*```\s*\z/, '').strip
  end

  def setup_model
    route = feature_route
    return @model = route[:model] if account_override_route?(route) || captain_v2_assistant?

    @model = @fallback_model.presence || installation_model.presence || route&.dig(:model) || DEFAULT_MODEL
  end

  def feature_route
    return if @llm_feature.blank?

    Llm::FeatureRouter.resolve(feature: @llm_feature, account: @llm_account)
  end

  def account_override_route?(route)
    route&.dig(:source) == :account_override
  end

  def captain_v2_assistant?
    @llm_feature.to_s == 'assistant' && @llm_account&.feature_enabled?('captain_integration_v2')
  end

  def installation_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
  end

  def setup_temperature
    @temperature = DEFAULT_TEMPERATURE
  end
end
