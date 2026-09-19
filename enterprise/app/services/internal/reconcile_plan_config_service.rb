class Internal::ReconcilePlanConfigService
  def perform
    # Synkra Chat: this whole service enforces Chatwoot's own paid-
    # Enterprise-license upsell on self-hosted "community" installs -
    # see reconcile_premium_config/reconcile_premium_features below
    # for what it used to silently undo, daily, before this fix. Left
    # as just clearing any stale warning flag from before this fix
    # existed, since premium_config_reset_required? below would
    # otherwise flag a false alarm every single day from here on -
    # our branding values are SUPPOSED to permanently differ from
    # Chatwoot's stock ones, that's the whole point of the rebrand.
    remove_premium_config_reset_warning
  end

  private

  def config_path
    @config_path ||= Rails.root.join('enterprise/config')
  end

  def premium_config
    @premium_config ||= YAML.safe_load(File.read("#{config_path}/premium_installation_config.yml")).freeze
  end

  def remove_premium_config_reset_warning
    Redis::Alfred.delete(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING)
  end

  def create_premium_config_reset_warning
    Redis::Alfred.set(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING, true)
  end

  def premium_config_reset_required?
    premium_config.any? do |config|
      config = config.with_indifferent_access
      existing_config = InstallationConfig.find_by(name: config[:name])
      existing_config&.value != config[:value] if existing_config.present?
    end
  end

  def reconcile_premium_config
    # Synkra Chat: no-op, deliberately - same reasoning as
    # reconcile_premium_features below. enterprise/config/
    # premium_installation_config.yml is entirely branding values
    # (INSTALLATION_NAME, LOGO, LOGO_DARK, LOGO_THUMBNAIL, BRAND_URL,
    # WIDGET_BRAND_URL, BRAND_NAME, ...) hardcoded back to stock
    # Chatwoot - this would silently undo the entire rebrand on the
    # same daily schedule that was stripping premium features. The
    # /brand-assets/logo_thumbnail.svg 404 seen in logs earlier this
    # session is very likely this having already fired once for
    # LOGO_THUMBNAIL specifically before this fix.
  end

  def premium_features
    @premium_features ||= YAML.safe_load(File.read("#{config_path}/premium_features.yml")).freeze
  end

  def reconcile_premium_features
    # Synkra Chat: no-op, deliberately. This method exists to enforce
    # Chatwoot's own paid-Enterprise-license upsell on self-hosted
    # "community" installs - it calls account.disable_features! on
    # every single account, once a day (Internal::TriggerDailyScheduledItemsJob,
    # midnight UTC), for anything listed in
    # enterprise/config/premium_features.yml (audit_logs, sla,
    # custom_roles, captain_integration, captain_document_auto_sync,
    # among others).
    #
    # That's exactly why SLA/Custom Roles/Audit Logs/the AI Agent's
    # backend kept reappearing disabled after being fixed - this ran
    # again the next midnight and silently reverted it, every time,
    # regardless of any manual fix or redeploy. We deliberately
    # enabled these features ourselves in config/features.yml; this
    # job enforcing Chatwoot's own commercial licensing doesn't apply
    # to our fork and shouldn't get to override that decision.
  end
end
