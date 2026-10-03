# frozen_string_literal: true

# Resolves which LLM provider to use for Captain's user-facing AI tasks
# and the AI Agent's auto-reply. Controlled by ENV['CAPTAIN_LLM_PROVIDER']
# (or the matching InstallationConfig for admin toggle without redeploy).
#
# Both providers can be configured simultaneously - Ollama stays in
# CAPTAIN_OPEN_AI_* (unchanged), Token Harbor lives in TOKEN_HARBOR_*.
# Switching is a single env var + container restart. Rollback is the same.
#
# Defaults to :ollama, which is a pure passthrough to the pre-existing
# CAPTAIN_OPEN_AI_* config reads. Nothing changes unless CAPTAIN_LLM_PROVIDER
# is explicitly set to token_harbor AND TOKEN_HARBOR_API_KEY is present.
module Captain::Llm::ProviderResolver
  OLLAMA_DEFAULT_ENDPOINT = 'http://ollama:11434'
  OLLAMA_DEFAULT_MODEL    = 'qwen2.5:3b-instruct-q4_K_M'
  TOKEN_HARBOR_DEFAULT_ENDPOINT = 'https://tokenharbor.ai/v1'
  TOKEN_HARBOR_DEFAULT_MODEL    = 'deepseek-v4.1-flash:free'

  module_function

  def resolve
    case active_provider
    when 'token_harbor'
      if ENV['TOKEN_HARBOR_API_KEY'].blank?
        Rails.logger.warn(
          '[Captain::Llm::ProviderResolver] CAPTAIN_LLM_PROVIDER=token_harbor ' \
          'but TOKEN_HARBOR_API_KEY is blank; falling back to ollama'
        )
        return ollama_config
      end
      token_harbor_config
    else
      ollama_config
    end
  end

  # Returns an ordered list of provider configs to try, primary first.
  # BaseTaskService iterates this list, catching exceptions and moving
  # to the next candidate. Used for resilience when the primary provider
  # is unavailable (rate-limited, down, key revoked).
  #
  # Fallback is only added when primary is NOT ollama - ollama has no
  # downstream fallback because it's the local last resort. Controlled
  # by CAPTAIN_LLM_FALLBACK_PROVIDER (default 'ollama'). Set to empty
  # string to disable fallback entirely.
  def resolve_candidates
    primary = resolve
    fallback_provider = ENV.fetch('CAPTAIN_LLM_FALLBACK_PROVIDER', 'ollama').to_s.strip

    return [primary] if fallback_provider.empty?
    return [primary] if primary[:provider] == fallback_provider

    fallback = config_for(fallback_provider)
    return [primary] if fallback.nil? || fallback[:api_key].blank?

    [primary, fallback]
  end

  def config_for(provider_name)
    case provider_name
    when 'ollama'       then ollama_config
    when 'token_harbor' then token_harbor_config
    end
  end

  def active_provider
    value = ENV['CAPTAIN_LLM_PROVIDER'].presence ||
            InstallationConfig.find_by(name: 'CAPTAIN_LLM_PROVIDER')&.value.presence
    value.to_s.downcase
  end

  def ollama_config
    {
      provider: 'ollama',
      endpoint: ollama_endpoint,
      api_key:  ollama_api_key,
      model:    ollama_model
    }
  end

  def token_harbor_config
    {
      provider: 'token_harbor',
      endpoint: ENV.fetch('TOKEN_HARBOR_ENDPOINT', TOKEN_HARBOR_DEFAULT_ENDPOINT),
      api_key:  ENV['TOKEN_HARBOR_API_KEY'],
      model:    ENV.fetch('TOKEN_HARBOR_MODEL', TOKEN_HARBOR_DEFAULT_MODEL)
    }
  end

  def ollama_endpoint
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence ||
      OLLAMA_DEFAULT_ENDPOINT
  end

  def ollama_api_key
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value.presence || 'ollama'
  end

  def ollama_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence ||
      OLLAMA_DEFAULT_MODEL
  end
end
