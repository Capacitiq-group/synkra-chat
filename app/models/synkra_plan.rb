# Synkra Chat billing: plan definitions. Deliberately a plain Ruby
# config, not a database table.
#
# Four real tiers, matching the Plan objects actually created on
# Paystack's dashboard (names/prices below are the source of truth -
# keep them in sync with Paystack, not the other way round). Per
# Refilwe: "we cap volume, not features" - every tier gets the same
# feature set; only messages/seats numbers differ.
#
# business_initiated_message_allowance and staff_limit are real, wired
# enforcement (not just display) as of the 12 Sep 2026 "Enforce message
# and seat limits per plan" commit - Message#enforce_synkra_billing_restriction
# (before_validation on message create) and
# AccountUser#ensure_within_synkra_seat_limit (validate on create).
# Both fail open (never block) if the subscription record itself can't
# be resolved - a billing-infra hiccup should never lock a business out
# of its own team or conversations.
#
# CONFIRMED 13 Sep 2026 (Refilwe) - the numbers below were placeholders
# until this date; they are now final. "Message" means every individual
# outgoing agent message (not grouped by conversation) - confirmed
# explicitly, matches this codebase's existing counting behavior
# unchanged. Once a plan's message allowance is used up, add-on packs
# (Billing::MessageAddon, same rate/pack structure as Flow's email
# add-ons) top it up - see that class for the purchase flow. Once the
# seat limit is hit, extra seats are R69/seat/month - see
# Billing::ExtraSeatService.
class SynkraPlan
  PLANS = {
    'free' => {
      name: 'Synkra Chat Free',
      price_zar: 0,
      staff_limit: 1,
      business_initiated_message_allowance: 250,
      storage_mb_allowance: 256,
      # No Paystack plan code - genuinely free, never goes through
      # checkout at all (only ever reached via change_plan/downgrade).
      paystack_plan_code: nil
    },
    'starter' => {
      name: 'Chat Starter',
      price_zar: 299,
      staff_limit: 7,
      business_initiated_message_allowance: 3000,
      storage_mb_allowance: 2048,
      paystack_plan_code: ENV.fetch('PAYSTACK_PLAN_CODE_STARTER', nil)
    },
    'business' => {
      name: 'Business',
      price_zar: 599,
      staff_limit: 15,
      business_initiated_message_allowance: 8000,
      storage_mb_allowance: 8192,
      paystack_plan_code: ENV.fetch('PAYSTACK_PLAN_CODE_BUSINESS', nil)
    },
    'pro' => {
      name: 'Chat Pro',
      price_zar: 999,
      staff_limit: 50,
      business_initiated_message_allowance: 25_000,
      storage_mb_allowance: 20_480,
      paystack_plan_code: ENV.fetch('PAYSTACK_PLAN_CODE_PRO', nil)
    }
  }.freeze

  # Confirmed 13 Sep 2026 (Refilwe): R69/seat/month for any seat beyond
  # the plan's staff_limit - see Billing::ExtraSeatService.
  EXTRA_SEAT_PRICE_ZAR = 69

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
