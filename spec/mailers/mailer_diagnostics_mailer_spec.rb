# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MailerDiagnosticsMailer do
  describe '#test_delivery' do
    it 'sends to the given address with transport details in the body' do
      mail = described_class.test_delivery(to: 'ops@example.com').deliver_now

      expect(mail.to).to eq(['ops@example.com'])
      expect(mail.subject).to include('SMTP test')
      expect(mail.body.encoded).to include('Sent via:')
      expect(mail.body.encoded).to include('SMTP host:')
    end
  end
end
