# Purely for verifying the SMTP pipeline is actually working -
# separate from every other mailer since it must NOT depend on
# liquid/DB-backed templates, EmailTemplate resolution, or anything
# else that could itself be the thing that's broken. If this fails,
# the problem is the SMTP transport itself (credentials, host,
# firewall) - not application logic. See
# lib/tasks/mailer_diagnostics.rake for how this gets triggered.
class MailerDiagnosticsMailer < ApplicationMailer
  def test_delivery(to:)
    mail(
      to: to,
      subject: "Synkra Chat SMTP test - #{Time.current.strftime('%d %b %Y %H:%M %Z')}",
      body: "This confirms outbound email is working end to end.\n\n" \
            "Sent via: #{ActionMailer::Base.delivery_method}\n" \
            "SMTP host: #{ActionMailer::Base.smtp_settings[:address]}\n" \
            "From: #{ActionMailer::Base.default[:from]}\n" \
            "If you're checking whether Resend specifically is wired up, the " \
            "SMTP host above should read smtp.resend.com."
    )
  end
end
