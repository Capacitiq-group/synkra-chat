module Billing::NotificationEmailAddonPack
  PACKS = [
    { key: 'pack_1k',  price_zar: 50,   units: 1_000 },
    { key: 'pack_2k',  price_zar: 100,  units: 2_000 },
    { key: 'pack_5k',  price_zar: 250,  units: 5_000 },
    { key: 'pack_10k', price_zar: 500,  units: 10_000 },
    { key: 'pack_20k', price_zar: 1_000, units: 20_000 }
  ].freeze

  def self.find(pack_key)
    PACKS.find { |pack| pack[:key] == pack_key.to_s }
  end

  def self.valid?(pack_key)
    find(pack_key).present?
  end
end
