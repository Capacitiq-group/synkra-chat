require 'rails_helper'

RSpec.describe Llm::Config do
  describe '.normalized_openai_base (via configure_ruby_llm)' do
    around do |example|
      original = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
      described_class.reset!
      example.run
      config = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')
      original.nil? ? config&.destroy : config&.update!(value: original)
      described_class.reset!
    end

    it 'appends /v1 to a bare host, matching every other CAPTAIN_OPEN_AI_ENDPOINT consumer' do
      InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_ENDPOINT', value: 'http://ollama:11434')

      described_class.initialize!

      expect(RubyLLM.config.openai_api_base).to eq('http://ollama:11434/v1')
    end

    it 'does not double-append /v1 if it is already present' do
      InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_ENDPOINT', value: 'http://ollama:11434/v1')

      described_class.initialize!

      expect(RubyLLM.config.openai_api_base).to eq('http://ollama:11434/v1')
    end
  end
end
