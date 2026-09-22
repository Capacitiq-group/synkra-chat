module Llm::FeatureRouter
  class UnknownFeatureError < StandardError; end

  CAPTAIN_V2_ASSISTANT_MODEL = 'gpt-5.2'.freeze

  class << self
    def resolve(feature:, account: nil)
      feature_key = feature.to_s
      raise UnknownFeatureError, "Unknown LLM feature: #{feature_key}" unless Llm::Models.feature?(feature_key)

      model, source = model_and_source(account, feature_key)

      {
        feature: feature_key,
        provider: provider_for(model, source),
        model: model,
        source: source
      }
    end

    private

    def model_and_source(account, feature_key)
      account_model = account_model_override(account, feature_key)
      return [account_model, :account_override] if account_model.present?

      # Synkra: a single installation-wide model (typically a self-hosted
      # Ollama model via CAPTAIN_OPEN_AI_ENDPOINT) that overrides every
      # Captain feature - editor (the reply-box sparkle icon), label
      # suggestion, FAQ generation, and so on - not just conversation_completion.
      # Mirrors what Llm::BaseAiService#setup_model already does directly for
      # its own feature family; this brings Captain::BaseTaskService's
      # features (which route only through here) in line with it.
      synkra_model = synkra_installation_model
      return [synkra_model, :installation_override] if synkra_model.present?

      installation_model = installation_model_override(feature_key)
      return [installation_model, :installation_override] if installation_model.present?

      [captain_v2_assistant_model(account, feature_key) || Llm::Models.default_model_for(feature_key), :default]
    end

    def synkra_installation_model
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence
    end

    def account_model_override(account, feature_key)
      model = account&.captain_models&.[](feature_key).presence
      return unless model
      return model if Llm::Models.valid_model_for?(feature_key, model)
    end

    def installation_model_override(feature_key)
      return unless feature_key == 'conversation_completion'
      return unless ChatwootApp.self_hosted_enterprise?

      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence
    end

    def provider_for(model, source)
      Llm::Models.provider_for(model) || ('openai' if source == :installation_override)
    end

    def captain_v2_assistant_model(account, feature_key)
      return unless feature_key == 'assistant'
      return unless account&.feature_enabled?('captain_integration_v2')

      CAPTAIN_V2_ASSISTANT_MODEL
    end
  end
end
