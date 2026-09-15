# Synkra Chat's central usage ledger. Every billable event is recorded
# here at the moment it happens - billing reads from this table, it
# never recomputes usage by scanning conversations/messages after the
# fact.
class SynkraUsageEvent < ApplicationRecord
  RESOURCE_TYPES = %w[business_initiated_message storage_mb ai_request voice_minute].freeze

  belongs_to :account

  validates :resource_type, inclusion: { in: RESOURCE_TYPES }
  validates :quantity, numericality: { greater_than: 0 }

  before_validation :set_occurred_at, on: :create

  def self.record!(account:, resource_type:, quantity: 1, source: nil, reference: nil)
    create!(
      account: account,
      resource_type: resource_type,
      quantity: quantity,
      source: source,
      reference_type: reference&.class&.name,
      reference_id: reference&.id
    )
  end

  private

  def set_occurred_at
    self.occurred_at ||= Time.current
  end
end
