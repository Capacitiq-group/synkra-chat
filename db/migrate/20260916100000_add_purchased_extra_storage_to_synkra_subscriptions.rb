class AddPurchasedExtraStorageToSynkraSubscriptions < ActiveRecord::Migration[7.2]
  # Storage model changed 16 Sep 2026 (Refilwe): NOT automatic overage
  # billing anymore - uploads are BLOCKED once over the plan allowance
  # plus any purchased extra storage, and the business must explicitly
  # buy more (R30/GB/month) to unblock, same purchase model as extra
  # seats (grant immediately, bill at next renewal, not prorated).
  # storage_overage_billed_for_reference (added 13 Sep) is reused for
  # this purchased-storage renewal charge's idempotency guard - same
  # need (Paystack redelivers webhooks, a redelivered renewal must
  # never bill twice), different meaning now (see
  # SynkraSubscription#bill_extra_storage_for_renewal!).
  #
  # last_storage_warning_threshold is deliberately separate from
  # last_usage_warning_threshold (messages) - storage doesn't reset
  # each period the way message usage does, so it must NOT be cleared
  # by start_new_period! the way the message one is, or a business
  # sitting at 95% storage for months would get re-notified every
  # single renewal.
  def change
    add_column :synkra_subscriptions, :purchased_extra_storage_gb, :integer, default: 0, null: false
    add_column :synkra_subscriptions, :last_storage_warning_threshold, :decimal
  end
end
