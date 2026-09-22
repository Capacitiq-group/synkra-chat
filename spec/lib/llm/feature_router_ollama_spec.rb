require 'rails_helper'

RSpec.describe Llm::FeatureRouter do
  describe '.resolve' do
    around do |example|
      original = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
      example.run
      config = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')
      original.nil? ? config&.destroy : config&.update!(value: original)
    end

    it 'applies CAPTAIN_OPEN_AI_MODEL to a feature that only conversation_completion used to reach' do
      InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_MODEL', value: 'qwen2.5:7b-instruct-q4_K_M')

      result = described_class.resolve(feature: 'editor')

      expect(result).to include(model: 'qwen2.5:7b-instruct-q4_K_M', source: :installation_override, provider: 'openai')
    end

    it 'falls back to the normal default when no installation model is set' do
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.destroy

      result = described_class.resolve(feature: 'editor')

      expect(result[:source]).to eq(:default)
      expect(result[:model]).to eq(Llm::Models.default_model_for('editor'))
    end
  end
end
