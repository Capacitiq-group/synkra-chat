# Marketing vs. transactional email

Built 13-14 Sep 2026, ahead of the ~20 Sep 2026 launch.

**Not a lawyer, not legal advice.** This was built to a reasonable,
conservative default (explicit opt-in required, easy one-click
unsubscribe, unsubscribing never affects transactional mail). Worth a
quick sanity-check with someone qualified before real marketing
content goes out under POPIA, especially for the Contact case below
where Capacitiq is providing infrastructure for its own customers to
market to *their* customers - three parties, not two.

## What was actually there before this

Audited every mailer in the codebase. All of them - conversation
replies, identity verification, security alerts, billing/usage
notices, portal setup instructions - are transactional. There was no
marketing/promotional email capability anywhere. So this wasn't a
"split" of mixed content; it's net-new consent infrastructure ahead of
having any marketing content to send.

## Two audiences, two different things

### 1. Capacitiq → Chat account users (the businesses paying Refilwe)

- `users.marketing_emails_opt_in` (boolean, default false)
- `MarketingMailer.broadcast(user:, subject:, body_html:)` - the
  **only** way marketing content should ever go out to this audience.
  Silently no-ops if the user hasn't opted in - callers don't need to
  check first. Always includes `List-Unsubscribe` /
  `List-Unsubscribe-Post` headers (a Gmail/Yahoo bulk-sender
  requirement since 2024, not just a courtesy) plus a visible
  unsubscribe link in the body.
- `GET /unsubscribe/marketing?token=...` - public, no login, token
  never expires (an old email's link must always still work). Uses
  Rails' built-in `signed_id`, no new token column needed.
- API: `marketing_emails_opt_in` is now a permitted param on
  `PUT /api/v1/profile` - a user can self-manage this once a frontend
  toggle exists (not built yet - see below).

### 2. A Chat business → its own end-customers (Contacts)

Different relationship entirely - Capacitiq isn't the sender here, the
business is. The **sending mechanism already exists**: Chatwoot's own
`Campaign` model can reach contacts through an inbox channel. What was
missing, and what got built, is just the consent layer:

- `contacts.marketing_opt_in` (boolean, default false)
- `GET /unsubscribe/business_marketing?token=...` - same pattern as
  above, `Contact#signed_id`
- API: `marketing_opt_in` is now a permitted param on the contacts
  API, so a business can mark consent however they capture it (a form,
  an import, etc.)

**Not built**: wiring Campaign's actual sending to check
`marketing_opt_in` before including a contact. Existing Campaigns are
mostly proactive/engagement-triggered (a chat widget popup while
someone's already on the business's site), which is a different legal
category from bulk marketing email - conflating the two by gating
*all* campaign sending on this new flag risked breaking existing
functionality without a clear signal that's actually wanted. If/when a
business wants to send genuine bulk marketing email through Campaigns,
that gate needs building deliberately, not as a side effect of this.

## Not built at all yet

- Frontend UI toggle for `marketing_emails_opt_in` (User) or
  `marketing_opt_in` (Contact) - both are API-ready, no visible
  checkbox anywhere yet.
- Anything that actually calls `MarketingMailer.broadcast` - no
  content exists yet (confirmed - this was built as plumbing ahead of
  content, not in response to a specific campaign).
- Campaign integration for Contact marketing (see above).
- A way for a Chat business's own admin to see/manage their contacts'
  marketing consent in bulk (only the single-contact API field
  exists).
