class AddStorageUsageToSynkraSubscriptions < ActiveRecord::Migration[7.2]
  # Storage tracking (confirmed by Refilwe 13 Sep 2026 - see
  # SynkraPlan's storage_mb_allowance/EXTRA_STORAGE_PRICE_ZAR_PER_GB).
  #
  # storage_used_mb is a CACHED value, recomputed periodically by
  # Billing::RecalculateStorageUsageJob (see that job for why: summing
  # ActiveStorage blob sizes per account is too expensive to do live on
  # every request, unlike messages/seats which are cheap COUNT queries).
  # storage_overage_billed_for_reference mirrors
  # extra_seats_billed_for_reference's idempotency pattern - storage
  # overage is billed automatically at each plan renewal (metered,
  # based on actual usage - NOT a pre-purchased quantity like extra
  # seats), and a redelivered renewal webhook must never charge twice.
  def change
    add_column :synkra_subscriptions, :storage_used_mb, :integer, default: 0, null: false
    add_column :synkra_subscriptions, :storage_overage_billed_for_reference, :string
  end
end
