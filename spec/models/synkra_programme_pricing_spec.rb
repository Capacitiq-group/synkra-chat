require 'rails_helper'

RSpec.describe SynkraPlan do
  describe '.for_programme' do
    it 'returns the standard config without a programme' do
      expect(described_class.for_programme('starter', nil)[:price_zar]).to eq(299)
    end

    it 'applies whole-rand student and community prices, keeping the plan limits' do
      student = described_class.for_programme('business', 'student')
      community = described_class.for_programme('business', 'community')

      expect(student[:price_zar]).to eq(389)
      expect(community[:price_zar]).to eq(239)
      expect(student[:staff_limit]).to eq(described_class.find('business')[:staff_limit])
    end

    it 'leaves the free plan alone' do
      expect(described_class.for_programme('free', 'student')[:price_zar]).to eq(0)
    end
  end
end

RSpec.describe SynkraProgrammeVerification do
  describe '.compose_student_email' do
    def compose(local, institution, extension)
      described_class.compose_student_email(local_part: local, institution: institution, extension: extension)
    end

    it 'builds the address from number, institution and extension' do
      expect(compose('1356456', 'ukzn', 'ac.za')).to eq(['1356456@ukzn.ac.za', nil])
    end

    it 'only accepts the listed extensions' do
      expect(compose('1356456', 'ukzn', 'com')).to eq([nil, :invalid_extension])
    end

    it 'rejects plus-addressing and an extension typed into the institution box' do
      expect(compose('a+b', 'ukzn', 'ac.za')).to eq([nil, :invalid_local_part])
      expect(compose('1356456', 'ukzn.ac.za', 'ac.za')).to eq([nil, :institution_includes_extension])
    end
  end
end
