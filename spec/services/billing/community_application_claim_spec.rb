require 'rails_helper'

RSpec.describe Billing::CommunityApplicationService, '.claim' do
  let(:account) { create(:account) }
  let(:applicant) { create(:user, email: 'org@example.org') }
  let(:someone_else) { create(:user, email: 'someone-else@example.com') }
  let(:verification) do
    SynkraProgrammeVerification.create!(
      account_id: nil, user_id: nil, programme: 'community', verification_method: 'application', status: 'verified',
      contact_email: 'org@example.org', access_token: 'ABC123XYZ0', expires_at: 1.year.from_now, verified_at: Time.current
    )
  end

  it 'claims successfully when the logged-in user email matches who applied' do
    verification
    result = described_class.claim(access_token: 'abc123xyz0', account: account, user: applicant)

    expect(result.success?).to be true
    verification.reload
    expect(verification.account_id).to eq(account.id)
    expect(verification.access_token).to be_nil
  end

  it 'refuses to claim when the logged-in user email does not match who applied' do
    verification
    result = described_class.claim(access_token: 'ABC123XYZ0', account: account, user: someone_else)

    expect(result.success?).to be false
    expect(result.code).to eq(:email_mismatch)
    expect(verification.reload.account_id).to be_nil
  end

  it 'cannot be claimed twice' do
    verification.claim!(account: account, user: applicant)
    second_account = create(:account)

    result = described_class.claim(access_token: 'ABC123XYZ0', account: second_account, user: applicant)

    expect(result.success?).to be false
    expect(result.code).to eq(:invalid_code)
  end
end
