# Synkra Chat billing: plan definitions. Deliberately a plain Ruby
# config, not a database table - there are only two plans by design
# ("a large catalogue of plans and feature add-ons" is explicitly what
# we're avoiding). Add-ons (AI, extra storage, voice, recording,
# transcription) are tracked separately once those features exist -
# this only covers what's actually built today.
class SynkraPlan
  PLANS = {
    'basic' => {
      name: 'Chat Basic',
      price_zar: 49,
      staff_limit: 3,
      business_initiated_message_allowance: 500,
      storage_mb_allowance: 1024,
      # Set once the corresponding Plan is created on Paystack's own
      # dashboard - required before real subscriptions can be created.
      paystack_plan_code: ENV.fetch('PAYSTACK_PLAN_CODE_BASIC', nil)
    },
    'pro' => {
      name: 'Chat Pro',
      price_zar: 149,
      staff_limit: 10,
      business_initiated_message_allowance: 2500,
      storage_mb_allowance: 5120,
      paystack_plan_code: ENV.fetch('PAYSTACK_PLAN_CODE_PRO', nil)
    }
  }.freeze

  # Usage-warning thresholds, matching the spec: notify at 70/90/100%,
  # hard stop only at 100% (never generate surprise debt).
  WARNING_THRESHOLDS = [0.7, 0.9, 1.0].freeze

  def self.find(plan_key)
    PLANS[plan_key.to_s] || PLANS['basic']
  end

  def self.valid?(plan_key)
    PLANS.key?(plan_key.to_s)
  end

  def self.names
    PLANS.keys
  end
end
