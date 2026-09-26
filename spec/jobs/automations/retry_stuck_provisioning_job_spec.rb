require 'rails_helper'

RSpec.describe Automations::RetryStuckProvisioningJob do
  describe '#perform' do
    it 'retries provisioning for an account stuck longer than the threshold' do
      account = create(:account)
      account.synkra_subscription.update!(created_at: 3.hours.ago)

      expect { described_class.perform_now }
        .to have_enqueued_job(Automations::ProvisionFlowJob).with(account.id)
    end

    it 'leaves a recently created (still legitimately retrying) account alone' do
      create(:account) # created_at defaults to now

      expect { described_class.perform_now }
        .not_to have_enqueued_job(Automations::ProvisionFlowJob)
    end

    it 'skips an account that already provisioned successfully' do
      account = create(:account)
      account.synkra_subscription.update!(
        created_at: 3.hours.ago,
        flow_api_key: 'SYN_already',
        flow_provisioned_at: 3.hours.ago
      )

      expect { described_class.perform_now }
        .not_to have_enqueued_job(Automations::ProvisionFlowJob)
    end
  end
end
