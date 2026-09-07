# Synkra Chat billing: plan definitions. Deliberately a plain Ruby
# config, not a database table.
#
# Four real tiers, matching the Plan objects actually created on
# Paystack's dashboard (names/prices below are the source of truth -
# keep them in sync with Paystack, not the other way round). Per
# Refilwe: "we cap volume, not features" - every tier gets the same
# feature set; only messages/seats numbers differ, and NONE of those
# numbers are enforced anywhere in the codebase yet (seats were never
# enforced; messages only ever gate on payment status via
# SynkraSubscription#outbound_blocked?, never on hitting the number
# below). These are purely for display (usage meter, warning emails)
# until/unless real enforcement gets built.
#
# staff_limit and business_initiated_message_allowance below are
# UNCONFIRMED PLACEHOLDERS - Refilwe gave prices and Paystack codes but
# not exact seat/message numbers ("more", "higher", "much higher" per
# tier). Flagging clearly rather than repeating the Pro-price mistake:
# these need a real decision, not a quiet guess treated as final.
class SynkraPlan
  PLANS = {
    'free' => {
      name: 'Synkra Chat Free',
      price_zar: 0,
      staff_limit: 1,
      business_initiated_message_allowance: 100,
      storage_mb_allowance: 256,
      # No Paystack plan code - genuinely free, never goes through
      # checkout at all (only ever reached via change_plan/downgrade).
      paystack_plan_code: nil
    },
    'starter' => {
      name: 'Chat Starter',
      price_zar: 299,
      staff_limit: 5,
      business_initiated_message_allowance: 1000,
      storage_mb_allowance: 2048,
      paystack_plan_code: ENV.fetch('PAYSTACK_PLAN_CODE_STARTER', nil)
    },
    'business' => {
      name: 'Business',
      price_zar: 599,
      staff_limit: 15,
      business_initiated_message_allowance: 4000,
      storage_mb_allowance: 8192,
      paystack_plan_code: ENV.fetch('PAYSTACK_PLAN_CODE_BUSINESS', nil)
    },
    'pro' => {
      name: 'Chat Pro',
      price_zar: 999,
      staff_limit: 30,
      business_initiated_message_allowance: 10_000,
      storage_mb_allowance: 20_480,
      paystack_plan_code: ENV.fetch('PAYSTACK_PLAN_CODE_PRO', nil)
    }
  }.freeze

  # Ranked lowest to highest - used by nothing in the backend today,
  # but keeping the hash insertion order meaningful (free < starter <
  # business < pro) costs nothing and matches how the frontend infers
  # upgrade vs. downgrade from PLANS.keys order.

  # Usage-warning thresholds, matching the spec: notify at 70/90/100%,
  # hard stop only at 100% (never generate surprise debt).
  WARNING_THRESHOLDS = [0.7, 0.9, 1.0].freeze

  def self.find(plan_key)
    PLANS[plan_key.to_s] || PLANS['free']
  end

  def self.valid?(plan_key)
    PLANS.key?(plan_key.to_s)
  end

  def self.names
    PLANS.keys
  end
end
