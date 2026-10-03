# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MarketingMailer do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let(:class_instance) { described_class.new }

  before do
    allow(described_class).to receive(:new).and_return(class_instance)
    allow(class_instance).to receive(:smtp_config_set_or_development?).and_return(true)
  end

  describe '#broadcast' do
    context 'when the user has not opted in' do
      it 'does not send anything - this is the single enforcement point, not the caller' do
        user.update!(marketing_emails_opt_in: false)
        mail = described_class.broadcast(user: user, subject: 'Hello', body_html: '<p>Hi</p>').deliver_now
        expect(mail.message).to be_a(ActionMailer::Base::NullMail)
      end
    end

    context 'when the user has opted in' do
      before { user.update!(marketing_emails_opt_in: true) }

      it 'sends to the user and includes List-Unsubscribe headers' do
        mail = described_class.broadcast(user: user, subject: 'Product update', body_html: '<p>New stuff</p>').deliver_now

        expect(mail.to).to eq([user.email])
        expect(mail.subject).to eq('Product update')
        expect(mail['List-Unsubscribe']).to be_present
        expect(mail['List-Unsubscribe-Post'].to_s).to eq('List-Unsubscribe=One-Click')
      end

      it 'embeds a working unsubscribe link in the body' do
        mail = described_class.broadcast(user: user, subject: 'Product update', body_html: '<p>New stuff</p>').deliver_now
        expect(mail.body.encoded).to include('/unsubscribe/marketing?token=')
      end
    end

    context 'when the user has no email' do
      it 'does not send' do
        user.update_column(:email, nil) # rubocop:disable Rails/SkipsModelValidations
        user.update!(marketing_emails_opt_in: true)
        mail = described_class.broadcast(user: user, subject: 'Hello', body_html: '<p>Hi</p>').deliver_now
        expect(mail.message).to be_a(ActionMailer::Base::NullMail)
      end
    end
  end
end
