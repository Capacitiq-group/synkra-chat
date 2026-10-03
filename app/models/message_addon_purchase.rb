# The audit trail for message add-on purchases - see the migration
# comment (db/migrate/20260913140000_create_message_addon_purchases.rb)
# and Billing::MessageAddonPack for the pack catalogue. Never mutated
# after completion; SynkraSubscription#purchased_message_credits is the
# live spendable balance this ledger explains.
class MessageAddonPurchase < ApplicationRecord
  STATUSES = %w[pending completed].freeze

  belongs_to :account

  validates :pack_key, inclusion: { in: Billing::MessageAddonPack::PACKS.map { |p| p[:key] } }
  validates :status, inclusion: { in: STATUSES }
  validates :paystack_reference, presence: true, uniqueness: true
end
