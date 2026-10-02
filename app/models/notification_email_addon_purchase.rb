class NotificationEmailAddonPurchase < ApplicationRecord
  STATUSES = %w[pending completed].freeze

  belongs_to :account

  validates :pack_key, inclusion: { in: Billing::NotificationEmailAddonPack::PACKS.map { |p| p[:key] } }
  validates :status, inclusion: { in: STATUSES }
  validates :paystack_reference, presence: true, uniqueness: true
end
