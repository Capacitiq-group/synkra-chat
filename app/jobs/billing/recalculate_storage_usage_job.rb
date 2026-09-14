# Recomputes Billing::StorageUsageCalculator for every account and
# caches the result on SynkraSubscription#storage_used_mb. Runs daily
# (see config/schedule.yml) - unlike messages/seats (cheap COUNT
# queries, checked live on every message/seat action), summing
# ActiveStorage blob sizes across an account's attachments is too
# expensive to compute on every request, so this trades some staleness
# (up to 24h) for not adding real query cost to hot paths like sending
# a message. That staleness is acceptable here: storage usage moves
# slowly compared to message volume, and nothing currently blocks on
# this number - see SynkraSubscription#bill_storage_overage_for_renewal!'s
# comment for why storage is billed automatically for actual overage
# rather than gating uploads.
class Billing::RecalculateStorageUsageJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      subscription = account.synkra_subscription
      next unless subscription

      subscription.update_column(:storage_used_mb, Billing::StorageUsageCalculator.new(account).total_mb) # rubocop:disable Rails/SkipsModelValidations
    rescue StandardError => e
      Rails.logger.error("[SynkraBilling] Failed to recalculate storage usage for account #{account.id}: #{e.message}")
    end
  end
end
