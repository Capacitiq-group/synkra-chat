# Message add-on packs. Confirmed by Refilwe (13 Sep 2026): same rate
# and pack structure as Flow's own email add-ons
# (synkra-client-hub/src/lib/billing/addon-packs.ts) - R0.01/message,
# non-expiring, R50 pack-price floor. A plain Ruby config, not a
# database table, matching SynkraPlan's own pattern.
module Billing::MessageAddonPack
  PACKS = [
    { key: 'pack_5k', price_zar: 50, units: 5_000 },
    { key: 'pack_10k', price_zar: 100, units: 10_000 },
    { key: 'pack_25k', price_zar: 250, units: 25_000 },
    { key: 'pack_50k', price_zar: 500, units: 50_000 },
    { key: 'pack_100k', price_zar: 1_000, units: 100_000 }
  ].freeze

  def self.find(pack_key)
    PACKS.find { |pack| pack[:key] == pack_key.to_s }
  end

  def self.valid?(pack_key)
    find(pack_key).present?
  end
end
