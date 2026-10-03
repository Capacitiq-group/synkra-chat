require 'rails_helper'

RSpec.describe SynkraSubscription do
  let(:account) { create(:account) }
  let(:subscription) { account.synkra_subscription }

  describe '#change_plan!' do
    it 'applies an upgrade immediately and enqueues a Flow sync' do
      expect { subscription.change_plan!('pro') }
        .to have_enqueued_job(Automations::SyncFlowPlanJob).with(account.id, 'pro')
      expect(subscription.reload.plan).to eq('pro')
      expect(subscription.pending_plan).to be_nil
      expect(subscription.plan_changed_at).to be_present
    end

    it 'schedules a downgrade for period end instead of applying it immediately' do
      subscription.update!(plan: 'pro', plan_changed_at: Time.current)

      expect { subscription.change_plan!('starter') }
        .not_to have_enqueued_job(Automations::SyncFlowPlanJob)
      expect(subscription.reload.plan).to eq('pro')
      expect(subscription.pending_plan).to eq('starter')
    end

    it 'ignores an invalid plan' do
      expect { subscription.change_plan!('not-a-real-plan') }
        .not_to(change { subscription.reload.plan })
    end
  end

  describe '#apply_pending_plan_change!' do
    it 'applies the pending downgrade and syncs Flow' do
      subscription.update!(plan: 'pro', pending_plan: 'starter')

      expect { subscription.apply_pending_plan_change! }
        .to have_enqueued_job(Automations::SyncFlowPlanJob).with(account.id, 'starter')
      expect(subscription.reload.plan).to eq('starter')
      expect(subscription.pending_plan).to be_nil
    end

    it 'does nothing when there is no pending plan' do
      expect { subscription.apply_pending_plan_change! }
        .not_to have_enqueued_job(Automations::SyncFlowPlanJob)
    end
  end

  describe '#plan_sync_stale?' do
    it 'is false when there is no shadow client yet' do
      subscription.update!(flow_provisioned_at: nil, plan_changed_at: 1.hour.ago, flow_plan_synced_at: nil)
      expect(subscription).not_to be_plan_sync_stale
    end

    it 'is false when the plan has never actually changed since provisioning' do
      subscription.update!(flow_provisioned_at: 1.hour.ago, plan_changed_at: nil)
      expect(subscription).not_to be_plan_sync_stale
    end

    it 'is true when a plan change has never been synced' do
      subscription.update!(flow_provisioned_at: 1.hour.ago, plan_changed_at: 30.minutes.ago, flow_plan_synced_at: nil)
      expect(subscription).to be_plan_sync_stale
    end

    it 'is true when the last sync predates the last plan change' do
      subscription.update!(
        flow_provisioned_at: 1.hour.ago,
        flow_plan_synced_at: 40.minutes.ago,
        plan_changed_at: 10.minutes.ago
      )
      expect(subscription).to be_plan_sync_stale
    end

    it 'is false when the last sync is at or after the last plan change' do
      subscription.update!(
        flow_provisioned_at: 1.hour.ago,
        plan_changed_at: 40.minutes.ago,
        flow_plan_synced_at: 10.minutes.ago
      )
      expect(subscription).not_to be_plan_sync_stale
    end
  end

  describe '#automations_credits' do
    it 'delegates to Automations::FlowClient scoped to this subscription' do
      flow_client = instance_double(Automations::FlowClient)
      expect(Automations::FlowClient).to receive(:new).with(subscription).and_return(flow_client)
      expect(flow_client).to receive(:credits)

      subscription.automations_credits
    end
  end

  describe '#effective_seat_limit' do
    it 'is the plan staff_limit plus purchased extra seats' do
      subscription.update!(plan: 'starter', purchased_extra_seats: 3)
      expect(subscription.effective_seat_limit).to eq(7 + 3)
    end
  end

  describe '#purchase_extra_seats!' do
    it 'rejects a non-positive quantity without touching Paystack' do
      expect(Billing::PaystackService).not_to receive(:new)
      result = subscription.purchase_extra_seats!(0)
      expect(result.success?).to be false
    end

    it 'rejects when there is no card on file' do
      subscription.update!(paystack_authorization_code: nil)
      expect(Billing::PaystackService).not_to receive(:new)
      result = subscription.purchase_extra_seats!(2)
      expect(result.success?).to be false
      expect(result.error).to match(/No card on file/)
    end

    it 'grants the seats immediately with NO charge - billing happens at the next renewal instead' do
      subscription.update!(paystack_authorization_code: 'AUTH_123', purchased_extra_seats: 1)
      expect(Billing::PaystackService).not_to receive(:new)

      expect { subscription.purchase_extra_seats!(2) }
        .to change { subscription.reload.purchased_extra_seats }.from(1).to(3)
    end
  end

  describe '#bill_extra_seats_for_renewal!' do
    before { subscription.update!(paystack_authorization_code: 'AUTH_123', purchased_extra_seats: 4) }

    it 'does nothing when there are no purchased extra seats' do
      subscription.update!(purchased_extra_seats: 0)
      expect(Billing::PaystackService).not_to receive(:new)
      subscription.bill_extra_seats_for_renewal!('txn_ref_1')
    end

    it 'does nothing without a reference, rather than risk an unguarded charge' do
      expect(Billing::PaystackService).not_to receive(:new)
      subscription.bill_extra_seats_for_renewal!(nil)
    end

    it 'charges for the FULL current seat count (not an increment) and stamps the reference' do
      paystack = instance_double(Billing::PaystackService)
      allow(Billing::PaystackService).to receive(:new).and_return(paystack)
      expect(paystack).to receive(:charge_authorization)
        .with(hash_including(amount_zar: 4 * SynkraPlan::EXTRA_SEAT_PRICE_ZAR))
        .and_return(Billing::PaystackService::Result.new(success?: true, data: {}))

      subscription.bill_extra_seats_for_renewal!('txn_ref_1')
      expect(subscription.reload.extra_seats_billed_for_reference).to eq('txn_ref_1')
    end

    it 'is idempotent - a redelivered webhook for the same renewal never charges twice' do
      subscription.update!(extra_seats_billed_for_reference: 'txn_ref_1')
      expect(Billing::PaystackService).not_to receive(:new)

      subscription.bill_extra_seats_for_renewal!('txn_ref_1')
    end

    it 'charges again for a genuinely new renewal (different reference)' do
      subscription.update!(extra_seats_billed_for_reference: 'txn_ref_1')
      paystack = instance_double(Billing::PaystackService)
      allow(Billing::PaystackService).to receive(:new).and_return(paystack)
      expect(paystack).to receive(:charge_authorization)
        .and_return(Billing::PaystackService::Result.new(success?: true, data: {}))

      subscription.bill_extra_seats_for_renewal!('txn_ref_2')
      expect(subscription.reload.extra_seats_billed_for_reference).to eq('txn_ref_2')
    end

    it 'fails open - a failed charge never removes seats the business already has' do
      paystack = instance_double(Billing::PaystackService)
      allow(Billing::PaystackService).to receive(:new).and_return(paystack)
      allow(paystack).to receive(:charge_authorization)
        .and_return(Billing::PaystackService::Result.new(success?: false, error: 'card declined'))

      expect { subscription.bill_extra_seats_for_renewal!('txn_ref_1') }
        .not_to(change { subscription.reload.purchased_extra_seats })
      expect(subscription.reload.extra_seats_billed_for_reference).to be_nil
    end
  end

  describe '#allowance_exhausted? and purchased message credits' do
    it 'is false while the plan allowance still has room, regardless of purchased credits' do
      allow(subscription).to receive(:business_initiated_messages_used).and_return(0)
      subscription.update!(purchased_message_credits: 0)
      expect(subscription).not_to be_allowance_exhausted
    end

    it 'is false once the plan allowance is used up if purchased credits remain' do
      allow(subscription).to receive(:plan_allowance_exhausted?).and_return(true)
      subscription.update!(purchased_message_credits: 10)
      expect(subscription).not_to be_allowance_exhausted
    end

    it 'is true only once both the plan allowance AND purchased credits are exhausted' do
      allow(subscription).to receive(:plan_allowance_exhausted?).and_return(true)
      subscription.update!(purchased_message_credits: 0)
      expect(subscription).to be_allowance_exhausted
    end
  end

  describe '#consume_purchased_message_credit_if_over_plan_allowance!' do
    it 'does not touch the purchased balance while plan allowance remains' do
      allow(subscription).to receive(:plan_allowance_exhausted?).and_return(false)
      subscription.update!(purchased_message_credits: 5)

      expect { subscription.consume_purchased_message_credit_if_over_plan_allowance! }
        .not_to(change { subscription.reload.purchased_message_credits })
    end

    it 'decrements the purchased balance by one once the plan allowance is exhausted' do
      allow(subscription).to receive(:plan_allowance_exhausted?).and_return(true)
      subscription.update!(purchased_message_credits: 5)

      expect { subscription.consume_purchased_message_credit_if_over_plan_allowance! }
        .to change { subscription.reload.purchased_message_credits }.from(5).to(4)
    end

    it 'never goes negative' do
      allow(subscription).to receive(:plan_allowance_exhausted?).and_return(true)
      subscription.update!(purchased_message_credits: 0)

      expect { subscription.consume_purchased_message_credit_if_over_plan_allowance! }
        .not_to(change { subscription.reload.purchased_message_credits })
    end
  end

  describe '#effective_storage_mb_allowance' do
    it 'is the plan allowance plus purchased extra storage' do
      subscription.update!(plan: 'starter', purchased_extra_storage_gb: 2) # starter allowance is 3072MB
      expect(subscription.effective_storage_mb_allowance).to eq(3072 + 2 * 1024)
    end
  end

  describe '#storage_blocked?' do
    it 'is false while usage is within the effective allowance' do
      subscription.update!(plan: 'starter', storage_used_mb: 1000)
      expect(subscription).not_to be_storage_blocked
    end

    it 'is true once usage reaches the effective allowance' do
      subscription.update!(plan: 'starter', storage_used_mb: 3072)
      expect(subscription).to be_storage_blocked
    end

    it 'accounts for purchased extra storage when deciding' do
      subscription.update!(plan: 'starter', storage_used_mb: 3072 + 500, purchased_extra_storage_gb: 1)
      expect(subscription).not_to be_storage_blocked
    end
  end

  describe '#purchase_extra_storage!' do
    it 'rejects a non-positive GB amount' do
      expect(Billing::PaystackService).not_to receive(:new)
      result = subscription.purchase_extra_storage!(0)
      expect(result.success?).to be false
    end

    it 'rejects when there is no card on file' do
      subscription.update!(paystack_authorization_code: nil)
      result = subscription.purchase_extra_storage!(2)
      expect(result.success?).to be false
      expect(result.error).to match(/No card on file/)
    end

    it 'grants the GB immediately with NO charge' do
      subscription.update!(paystack_authorization_code: 'AUTH_123', purchased_extra_storage_gb: 1)
      expect(Billing::PaystackService).not_to receive(:new)

      expect { subscription.purchase_extra_storage!(2) }
        .to change { subscription.reload.purchased_extra_storage_gb }.from(1).to(3)
    end
  end

  describe '#bill_extra_storage_for_renewal!' do
    before do
      subscription.update!(
        plan: 'starter', purchased_extra_storage_gb: 1,
        paystack_authorization_code: 'AUTH_123'
      )
    end

    it 'does nothing when there is no purchased extra storage' do
      subscription.update!(purchased_extra_storage_gb: 0)
      expect(Billing::PaystackService).not_to receive(:new)
      subscription.bill_extra_storage_for_renewal!('txn_ref_1')
    end

    it 'does nothing without a reference' do
      expect(Billing::PaystackService).not_to receive(:new)
      subscription.bill_extra_storage_for_renewal!(nil)
    end

    it 'does nothing without a card on file - fails open, never blocks' do
      subscription.update!(paystack_authorization_code: nil)
      expect(Billing::PaystackService).not_to receive(:new)
      subscription.bill_extra_storage_for_renewal!('txn_ref_1')
    end

    it 'charges purchased_extra_storage_gb * EXTRA_STORAGE_PRICE_ZAR_PER_GB and stamps the reference' do
      paystack = instance_double(Billing::PaystackService)
      allow(Billing::PaystackService).to receive(:new).and_return(paystack)
      expect(paystack).to receive(:charge_authorization)
        .with(hash_including(amount_zar: 1 * SynkraPlan::EXTRA_STORAGE_PRICE_ZAR_PER_GB))
        .and_return(Billing::PaystackService::Result.new(success?: true, data: {}))

      subscription.bill_extra_storage_for_renewal!('txn_ref_1')
      expect(subscription.reload.storage_overage_billed_for_reference).to eq('txn_ref_1')
    end

    it 'is idempotent - a redelivered webhook for the same renewal never bills twice' do
      subscription.update!(storage_overage_billed_for_reference: 'txn_ref_1')
      expect(Billing::PaystackService).not_to receive(:new)

      subscription.bill_extra_storage_for_renewal!('txn_ref_1')
    end

    it 'fails open on a failed charge - never touches the billed-for-reference stamp' do
      paystack = instance_double(Billing::PaystackService)
      allow(Billing::PaystackService).to receive(:new).and_return(paystack)
      allow(paystack).to receive(:charge_authorization)
        .and_return(Billing::PaystackService::Result.new(success?: false, error: 'card declined'))

      subscription.bill_extra_storage_for_renewal!('txn_ref_1')
      expect(subscription.reload.storage_overage_billed_for_reference).to be_nil
    end
  end
end
