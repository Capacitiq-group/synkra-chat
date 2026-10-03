# Synkra Chat global identity layer: manages the "trusted device" cookie
# that lets a returning, already-OTP-verified person skip re-verification
# when they contact a different business.
#
# KNOWN LIMITATION: the widget is usually embedded in an iframe on a
# business's own website, making this a third-party cookie from the
# browser's perspective. Safari blocks third-party cookies by default
# already, and Chrome is moving the same direction - so on those
# browsers this cookie won't persist, and OTP will be requested more
# often than the ideal "verify once" experience described. It still
# works correctly for the standalone widget page (visited directly,
# not iframed) and for browsers that allow third-party cookies. A fully
# robust fix (e.g. the Storage Access API, or a top-level-navigation
# handoff) is a larger piece of work for later, not attempted here.
module TrustedDeviceHelper
  TRUSTED_DEVICE_COOKIE = :synkra_identity

  def trusted_global_user
    token = cookies.signed[TRUSTED_DEVICE_COOKIE]
    SynkraGlobalUser.find_by_trust_token(token)
  end

  def set_trusted_device_cookie(global_user)
    cookies.signed[TRUSTED_DEVICE_COOKIE] = {
      value: global_user.generate_trust_token,
      expires: SynkraGlobalUser::TRUST_DURATION.from_now,
      httponly: true,
      secure: true,
      same_site: :none
    }
  end
end
