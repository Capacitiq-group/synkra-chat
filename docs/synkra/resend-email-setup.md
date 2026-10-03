# Resend email delivery — setup and verification

Flagged in the original handover as "genuinely unknown - never
verified." This app's mailer config
(`config/initializers/mailer.rb`) is pure generic SMTP - **no code
changes are needed for Resend specifically**, only the right env
vars. Resend's SMTP relay is a drop-in.

## Env vars to set

| Var | Value |
|---|---|
| `SMTP_ADDRESS` | `smtp.resend.com` |
| `SMTP_PORT` | `587` |
| `SMTP_AUTHENTICATION` | `login` |
| `SMTP_USERNAME` | `resend` (literally the word "resend", not your account email) |
| `SMTP_PASSWORD` | Your Resend API key (starts with `re_`) |
| `SMTP_ENABLE_STARTTLS_AUTO` | `true` (this is the default already, no need to set explicitly) |
| `MAILER_SENDER_EMAIL` | e.g. `Synkra Chat <notifications@synkra.co.za>` - the domain **must** be verified in Resend (see below) |

## The step that actually determines whether this works: domain verification

SMTP credentials being correct is necessary but not sufficient.
Resend requires the sending domain (whatever's after the `@` in
`MAILER_SENDER_EMAIL`) to be verified in the Resend dashboard - add
their SPF/DKIM DNS records for that domain. Without this:
- In Resend's sandbox/test mode, you can only send to your own
  Resend account's verified email address - everything else fails
  or silently doesn't arrive.
- Even once out of sandbox, an unverified domain gets much worse
  deliverability (spam-foldered or outright rejected), independent
  of whether the SMTP credentials themselves were accepted.

This is a Resend dashboard step, not something set in this codebase.

## Verifying it actually works

Two rake tasks were built for this (`lib/tasks/mailer_diagnostics.rake`):

```bash
# 1. Confirm the server is actually configured to use Resend at all
#    (never prints the password/API key itself)
docker exec -it rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rake mailer:config_check

# 2. Send a real end-to-end test email
docker exec -it rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rake mailer:send_test[you@example.com]
```

`send_test` uses a deliberately minimal mailer
(`MailerDiagnosticsMailer`) with no liquid templates or database
dependencies - if it fails, the problem is the SMTP transport itself
(credentials, host reachability, Resend API key validity), not
application logic elsewhere. A successful send confirms SMTP auth
succeeded; it does NOT by itself confirm inbox placement - actually
check the test inbox (and spam folder).

## What this does NOT verify

- Whether `RAILS_INBOUND_EMAIL_SERVICE` (for receiving email into
  conversations, a completely separate concern from outbound) is
  configured - Resend is an outbound-only concern here.
- Deliverability at scale/reputation over time - a single successful
  test send doesn't guarantee every production email lands in the
  inbox going forward.
