class UserSessionTrackingService
  # CFNetwork UAs cannot distinguish iPhone from iPad; both get labelled iPhone here.
  LEGACY_MOBILE_UAS = [
    { match: %r{\Aokhttp/}, platform: 'Android', device: 'Android' },
    { match: %r{\AChatwoot/.*CFNetwork.*Darwin}, platform: 'iPhone', device: 'iPhone' }
  ].freeze
  private_constant :LEGACY_MOBILE_UAS

  def initialize(user:, request:, client_id:)
    @user = user
    @request = request
    @client_id = client_id
  end

  def create_or_update!
    session = @user.user_sessions.find_or_initialize_by(client_id: @client_id)
    ip = @request.remote_ip
    # Checked BEFORE this session's own row is updated below - if this
    # exact device/session already had this ip on file, its own
    # existing row already matches, so this correctly treats "same
    # device, same network, just refreshing" as known. Only a truly
    # new IP, across every device this user has ever signed in from,
    # trips the notification below. A user's very first-ever login has
    # no history to compare against, so it's never treated as "new" -
    # there's nothing anomalous about it.
    has_prior_sessions = @user.user_sessions.exists?
    known_ip = ip.blank? || !has_prior_sessions || @user.user_sessions.where(ip_address: ip).exists?

    session.assign_attributes(session_attributes)
    session.last_activity_at = Time.current
    session.save!
    UserSessionIpLookupJob.perform_later(session) if session.ip_address.present?
    notify_new_ip_login(session) unless known_ip
    session
  end

  def update_activity!
    session = @user.user_sessions.find_by(client_id: @client_id)
    return unless session&.should_update_activity?

    session.update_columns(last_activity_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def notify_new_ip_login(session)
    UserSecurityMailer.new_login_notification(user: @user, session: session).deliver_later
  rescue StandardError => e
    # Never let a notification failure interfere with an otherwise
    # successful login.
    Rails.logger.error "[UserSessionTrackingService] Failed to queue new-login notification for user #{@user.id}: #{e.message}"
  end

  def session_attributes
    client_headers = mobile_client_headers
    if client_headers
      return client_headers.merge(
        ip_address: @request.remote_ip,
        user_agent: @request.user_agent
      )
    end

    browser = Browser.new(@request.user_agent)

    attrs = {
      ip_address: @request.remote_ip,
      user_agent: @request.user_agent,
      browser_name: browser.name,
      browser_version: browser.full_version,
      device_name: browser.device.name,
      platform_name: browser.platform.name,
      platform_version: browser.platform.version
    }

    patch_for_legacy_mobile(attrs)
  end

  def mobile_client_headers
    name = @request.headers['X-Chatwoot-Client-Name']
    return nil if name.blank?

    platform = @request.headers['X-Chatwoot-Platform']
    model = @request.headers['X-Chatwoot-Device-Model']

    {
      browser_name: name,
      browser_version: @request.headers['X-Chatwoot-Client-Version'],
      device_name: device_name_for_icon(platform, model),
      platform_name: model,
      platform_version: @request.headers['X-Chatwoot-Platform-Version']
    }
  end

  def device_name_for_icon(platform, model)
    normalized_platform = platform.to_s.downcase
    return 'iPad' if normalized_platform == 'ios' && model.to_s.include?('iPad')
    return 'iPhone' if normalized_platform == 'ios'

    'Android'
  end

  def patch_for_legacy_mobile(attrs)
    return attrs unless attrs[:browser_name] == 'Unknown Browser'

    hit = LEGACY_MOBILE_UAS.find { |m| @request.user_agent.to_s.match?(m[:match]) }
    return attrs unless hit

    attrs.merge(
      browser_name: 'Chatwoot Mobile',
      browser_version: nil,
      platform_name: hit[:platform],
      platform_version: nil,
      device_name: hit[:device]
    )
  end
end
