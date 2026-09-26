# Capacitiq's own marketing email to Chat account admins/agents (NOT
# end-customers - a Chat business's own marketing to ITS customers is
# a different relationship entirely, sent via Chatwoot's existing
# Campaign feature rather than a new mailer; see
# Contact#marketing_opt_in and ContactMarketingUnsubscriptionsController
# for the consent/unsubscribe side of that, built separately).
# Distinct from every other mailer in this app, which are all
# transactional (see the migration comment for the audit that
# established this) - this is the first and only mailer that sends
# anything promotional, so it's the one place opt-in and unsubscribe
# actually matter.
#
# NEVER send marketing content through any other mailer "for
# convenience" - transactional mail is exempt from consent
# requirements precisely because it's operationally necessary, not
# promotional. Mixing the two blurs that line and risks the exemption
# for everything else.
class MarketingMailer < ApplicationMailer
  # Only ever call this - never call `mail`/`send_mail_with_liquid`
  # directly for marketing content. Silently no-ops (not an error) if
  # the user hasn't opted in - the caller doesn't need to check first,
  # this is the single enforcement point.
  def broadcast(user:, subject:, body_html:)
    return unless smtp_config_set_or_development?
    return if user.email.blank?
    return unless user.marketing_emails_opt_in?

    @user = user
    @body_html = body_html
    unsubscribe_url = "#{root_url}unsubscribe/marketing?token=#{unsubscribe_token(user)}"

    # List-Unsubscribe (+ List-Unsubscribe-Post for the one-click
    # variant) is a deliverability requirement, not just a courtesy -
    # Gmail/Yahoo enforce this for bulk senders as of their 2024 bulk
    # sender policies; missing it risks mail being spam-foldered or
    # outright rejected regardless of consent being properly obtained.
    headers['List-Unsubscribe'] = "<#{unsubscribe_url}>"
    headers['List-Unsubscribe-Post'] = 'List-Unsubscribe=One-Click'
    @unsubscribe_url = unsubscribe_url

    send_mail_with_liquid(to: user.email, subject: subject)
  end

  private

  def unsubscribe_token(user)
    user.signed_id(purpose: :unsubscribe_marketing, expires_in: nil) # never expires - an old email's unsubscribe link must always still work
  end

  def liquid_locals
    super.merge({ user: @user, body_html: @body_html, unsubscribe_url: @unsubscribe_url })
  end
end
