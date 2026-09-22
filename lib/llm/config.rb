require 'ruby_llm'

module Llm::Config
  DEFAULT_MODEL = 'gpt-4.1-mini'.freeze

  class << self
    def initialized?
      @initialized ||= false
    end

    def initialize!
      return if @initialized

      configure_ruby_llm
      @initialized = true
    end

    def reset!
      @initialized = false
    end

    def with_api_key(api_key, api_base: nil)
      initialize!
      context = RubyLLM.context do |config|
        config.openai_api_key = api_key
        config.openai_api_base = api_base
      end

      yield context
    end

    private

    def configure_ruby_llm
      RubyLLM.configure do |config|
        config.openai_api_key = system_api_key if system_api_key.present?
        config.openai_api_base = normalized_openai_base if openai_endpoint.present?
        config.model_registry_file = Rails.root.join('config/llm_models.json').to_s
        config.logger = Rails.logger
      end
    end

    # Every other CAPTAIN_OPEN_AI_ENDPOINT consumer (Captain::BaseTaskService,
    # Integrations::LlmBaseService, Integrations::Openai::KeyValidator,
    # Enterprise::Concerns::Article) treats the stored value as a bare host
    # and appends /v1 itself, with 'https://api.openai.com/' -> '.../v1' as
    # their fallback. Match that convention here too, so one
    # CAPTAIN_OPEN_AI_ENDPOINT value (e.g. an Ollama host) works the same way
    # across both this global RubyLLM.configure path and those call sites,
    # instead of needing a different-shaped value for each.
    def normalized_openai_base
      base = openai_endpoint.to_s.chomp('/')
      base.end_with?('/v1') ? base : "#{base}/v1"
    end

    def system_api_key
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
    end

    def openai_endpoint
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
    end
  end
end
