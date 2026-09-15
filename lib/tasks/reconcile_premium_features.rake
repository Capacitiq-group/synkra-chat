# Undoes lingering damage from the bug documented in
# Internal::ReconcilePlanConfigService: before that fix landed,
# Internal::TriggerDailyScheduledItemsJob ran
# reconcile_premium_features every midnight UTC, silently disabling
# these features on every account because this fork reports as being
# on Chatwoot's free community plan. The fix stops it happening AGAIN
# - it does not retroactively re-enable a feature on an account that
# was already stripped before the fix deployed. This task does that
# one-time catch-up.
#
# Safe to re-run - enable_features! is idempotent, and this only ever
# turns features ON, matching what config/features.yml already
# declares as the intended state for every account on this fork. It
# never disables anything.
namespace :accounts do
  desc 'Re-enable premium features (AI Agent, SLA, Audit Logs, Custom Roles, etc.) on every account'
  task reconcile_premium_features: :environment do
    features = YAML.safe_load(File.read(Rails.root.join('enterprise/config/premium_features.yml')))
    puts "Re-enabling on every account: #{features.join(', ')}"

    count = 0
    Account.find_each do |account|
      account.enable_features!(*features)
      count += 1
    end

    puts "Done - reconciled #{count} account(s)."
  end

  desc 'Check whether any account is missing a premium feature it should have (read-only, no changes)'
  task check_premium_features: :environment do
    features = YAML.safe_load(File.read(Rails.root.join('enterprise/config/premium_features.yml')))
    any_missing = false

    Account.find_each do |account|
      missing = features.reject { |f| account.feature_enabled?(f) }
      next if missing.empty?

      any_missing = true
      puts "Account #{account.id} (#{account.name}) missing: #{missing.join(', ')}"
    end

    puts 'All accounts have every premium feature enabled.' unless any_missing
  end
end
