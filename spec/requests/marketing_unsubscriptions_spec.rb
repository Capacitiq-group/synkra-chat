require 'rails_helper'

RSpec.describe 'Marketing unsubscribe', type: :request do
  describe 'GET /unsubscribe/marketing' do
    let!(:account) { create(:account) }
    let!(:user) { create(:user, account: account, marketing_emails_opt_in: true) }

    it 'opts the user out with a valid token' do
      token = user.signed_id(purpose: :unsubscribe_marketing, expires_in: nil)
      get "/unsubscribe/marketing?token=#{token}"

      expect(response).to have_http_status(:success)
      expect(user.reload.marketing_emails_opt_in).to be false
    end

    it 'does not opt anyone out with an invalid token' do
      get '/unsubscribe/marketing?token=not-a-real-token'

      expect(response).to have_http_status(:success)
      expect(user.reload.marketing_emails_opt_in).to be true
    end

    it 'rejects a token signed for a different purpose' do
      token = user.signed_id(purpose: :something_else, expires_in: nil)
      get "/unsubscribe/marketing?token=#{token}"

      expect(user.reload.marketing_emails_opt_in).to be true
    end
  end

  describe 'GET /unsubscribe/business_marketing' do
    let!(:account) { create(:account) }
    let!(:contact) { create(:contact, account: account, marketing_opt_in: true) }

    it 'opts the contact out with a valid token' do
      token = contact.signed_id(purpose: :unsubscribe_marketing, expires_in: nil)
      get "/unsubscribe/business_marketing?token=#{token}"

      expect(response).to have_http_status(:success)
      expect(contact.reload.marketing_opt_in).to be false
    end

    it 'does not opt anyone out with an invalid token' do
      get '/unsubscribe/business_marketing?token=not-a-real-token'

      expect(response).to have_http_status(:success)
      expect(contact.reload.marketing_opt_in).to be true
    end
  end
end
