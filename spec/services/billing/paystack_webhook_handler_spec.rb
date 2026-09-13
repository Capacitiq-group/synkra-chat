require 'rails_helper'

RSpec.describe Billing::PaystackWebhookHandler do
  let(:account) { create(:account) }
  let(:subscription) { account.synkra_subscription }

  def charge_success_event(metadata:, reference: 'txn_1', authorization: {})
    {
      'event' => 'charge.success',
      'data' => { 'reference' => reference, 'metadata' => metadata, 'authorization' => authorization }
    }
  end

  describe '#process! for charge.success' do
    context 'when it is a genuine plan renewal (no purchase_type metadata)' do
      it 'runs the normal subscription-lifecycle logic' do
        event = charge_success_event(metadata: { 'synkra_account_id' => account.id.to_s })

        expect(subscription).to receive(:mark_active!)
        expect(subscription).to receive(:start_new_period!)
        expect(subscription).to receive(:apply_pending_plan_change!)
        allow(SynkraSubscription).to receive(:find_by).and_return(subscription)

        described_class.new(event).process!
      end
    end

    context 'when it is a message add-on purchase' do
      it 'credits the purchase and never touches subscription lifecycle methods' do
        purchase = MessageAddonPurchase.create!(
          account_id: account.id, pack_key: 'pack_5k', units: 5_000,
          price_zar: 50, paystack_reference: 'txn_addon_1', status: 'pending'
        )
        event = charge_success_event(
          metadata: { 'synkra_account_id' => account.id.to_s, 'purchase_type' => 'message_addon' },
          reference: 'txn_addon_1'
        )

        expect(subscription).not_to receive(:start_new_period!)
        expect(subscription).not_to receive(:mark_active!)

        expect { described_class.new(event).process! }
          .to change { subscription.reload.purchased_message_credits }.by(5_000)
        expect(purchase.reload.status).to eq('completed')
      end

      it 'is idempotent - a redelivered webhook for an already-completed purchase does not double-credit' do
        MessageAddonPurchase.create!(
          account_id: account.id, pack_key: 'pack_5k', units: 5_000,
          price_zar: 50, paystack_reference: 'txn_addon_1', status: 'completed'
        )
        subscription.update!(purchased_message_credits: 5_000)
        event = charge_success_event(
          metadata: { 'synkra_account_id' => account.id.to_s, 'purchase_type' => 'message_addon' },
          reference: 'txn_addon_1'
        )

        expect { described_class.new(event).process! }
          .not_to(change { subscription.reload.purchased_message_credits })
      end
    end

    context 'when it is an extra-seats charge (the bug caught before shipping)' do
      it 'is a pure no-op - never touches subscription lifecycle methods' do
        event = charge_success_event(
          metadata: { 'synkra_account_id' => account.id.to_s, 'purchase_type' => 'extra_seats' }
        )

        expect(SynkraSubscription).not_to receive(:find_by)
        expect(subscription).not_to receive(:start_new_period!)
        expect(subscription).not_to receive(:mark_active!)

        described_class.new(event).process!
      end
    end

    context 'plan renewal with purchased extra seats' do
      it 'bills the current extra-seat count using the renewal charge reference' do
        subscription.update!(paystack_authorization_code: 'AUTH_1', purchased_extra_seats: 3)
        event = charge_success_event(
          metadata: { 'synkra_account_id' => account.id.to_s }, reference: 'renewal_txn_1'
        )
        allow(SynkraSubscription).to receive(:find_by).and_return(subscription)

        paystack = instance_double(Billing::PaystackService)
        allow(Billing::PaystackService).to receive(:new).and_return(paystack)
        allow(paystack).to receive(:charge_authorization)
          .with(hash_including(amount_zar: 3 * SynkraPlan::EXTRA_SEAT_PRICE_ZAR))
          .and_return(Billing::PaystackService::Result.new(success?: true, data: {}))

        described_class.new(event).process!
        expect(subscription.reload.extra_seats_billed_for_reference).to eq('renewal_txn_1')
      end
    end
  end
end
