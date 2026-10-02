# Handover — 24 Sep 2026 — Email Inbox feature (not started, spec + research only)

## Status: nothing built yet

This session did research and locked two decisions, per explicit
instruction from the founder (Refilwe) to hand off before writing any
code, so the next session should read this fully before touching
anything. No migrations, models, controllers, or frontend work exist
for this feature yet.

## The feature, in the founder's own words (verbatim spec)

### Synkra Chat Email Integration

**1. Customer chooses "Connect Email" in Synkra Chat**

They enter the email address they currently use for customer
enquiries, for example: `info@business.co.za`

Synkra does **not** ask for their Gmail or Microsoft password and does
**not** request mailbox-wide OAuth access.

**2. Synkra creates a unique inbound address**

Synkra generates a unique address for that Chat inbox, e.g.
`abc123@inbound.synkra.co.za`, associated internally with the
customer's Synkra Chat inbox.

Database relationship: `abc123@inbound.synkra.co.za` → `Chat Inbox #123`

**3. Synkra displays forwarding instructions**

"Forward incoming messages from `info@business.co.za` to
`abc123@inbound.synkra.co.za`." Provider-specific instructions for
Gmail, Microsoft 365, etc.

**4. Customer adds the forwarding address to their email provider**

E.g. in Gmail: Settings → Forwarding → Add a forwarding address →
`abc123@inbound.synkra.co.za`. Google sends its verification email to
that address.

**5. Resend receives the verification email**

`Google → abc123@inbound.synkra.co.za → Resend → Synkra webhook`

**6. Synkra identifies the verification email**

Backend checks the incoming email against the expected verification
flow, extracts the relevant verification link/confirmation info. UI
shows: "Email verification detected — Google has sent a verification
email to your Synkra forwarding address. [Verify forwarding]" — they
click through.

**One explicit change from an earlier idea, stated directly by the
founder:** do NOT automatically expose Google's verification link to
the user unless/until verified acceptable under the provider's terms
and technically safe. The safer first implementation is "We've
received the verification email. Open it here / follow these
instructions to complete verification" — not an automated one-click
auto-click-the-link flow. Automate further only after testing Gmail
and Microsoft thoroughly.

**7. Customer completes forwarding verification**

Google/Microsoft confirms the destination is authorised via their own
normal verification process. Synkra isn't bypassing any provider
security — the customer completes the provider's standard flow.

**8. Customer emails now enter Synkra**

`Customer → info@business.co.za → (forwarded) → abc123@inbound.synkra.co.za → Resend → Synkra Email Webhook`

Synkra then: identifies the Chat inbox, identifies sender/recipient,
extracts subject/body, processes attachments, creates or updates the
conversation, displays it inside Synkra Chat.

**9. Synkra threads subsequent emails**

Must use `Message-ID` / `In-Reply-To` / `References` headers alongside
Synkra's own conversation ID, so replies don't each become a new
conversation. **Confirmed via research (see below): this is NOT
automatic — must be built.**

**10. Business replies from Synkra**

`Business → Synkra Chat → Synkra backend → Resend → Customer`,
received as an ordinary email conversation.

### Architecture diagram (founder's own ASCII, keep as reference)

```
CUSTOMER'S BUSINESS EMAIL
        │ forwarding
        ▼
abc123@inbound.synkra.co.za
        │
        ▼
   RESEND INBOUND
        │ webhook
        ▼
 SYNKRA EMAIL SERVICE
        ├── identify inbox
        ├── identify conversation
        ├── parse email
        ├── process attachments
        └── store message
        │
        ▼
     SYNKRA CHAT
        │ reply
        ▼
   SYNKRA EMAIL SERVICE
        │
        ▼
      RESEND
        │
        ▼
     CUSTOMER
```

**Synkra controls:** the unique inbound address, the mapping to the
Chat inbox, the webhook, email parsing, conversation/threading,
message storage, attachments, the Chat interface, outbound replies,
onboarding, connection status.

**The customer controls:** their existing business mailbox, whether
they enable forwarding, their Google/Microsoft verification, which
emails get forwarded, their own email-provider settings.

**Resend controls:** inbound email infrastructure, receiving the
email, parsing/normalising the message, delivering the webhook,
outbound email delivery.

## Research findings (this session, verified against Resend's own
current docs/pricing — primary sources, not third-party blogs)

- **Pricing (resend.com/pricing.md, authoritative)**: Free 3,000
  emails/mo (100/day cap, 1 domain); Pro $20/mo for 50,000; Scale
  $90/mo for 100,000 scaling to $1,150/mo for 2.5M; overage $0.90 down
  to $0.46 per 1,000 at higher Scale tiers.
- **Critical cost detail**: sent AND received emails share the same
  monthly quota. Every customer-forwarded inbound email and every
  outbound reply both burn one unit each. Budget roughly 2x raw
  conversation volume when estimating Resend costs for this feature.
- **Rate limit**: 5 requests/second, shared across the entire Resend
  **account/team** (not per domain, not per customer) — confirmed via
  a third-party technical comparison, not Resend's own docs directly,
  so treat as directionally correct but worth re-confirming against
  Resend support/docs before this becomes a real bottleneck. Fine at
  modest scale; worth monitoring as inbound email volume grows,
  especially since it's now shared with Chat's own existing system
  email (confirmation, billing, notification emails) — see decision
  below.
- **Domains**: only ONE domain needs receiving enabled
  (`inbound.synkra.co.za`), since routing happens by the `to` address
  within one webhook stream — this does NOT scale per-customer. No
  need for the paid "100 extra domains" add-on for this feature's core
  design (unique local-part per customer, not unique domain).
- **Threading is NOT automatic** for the standard webhook-based
  inbound flow. The webhook gives you the raw `Message-ID` header;
  Synkra's own backend must track `In-Reply-To`/`References` and pass
  them back explicitly when sending replies (via
  `previous_references`/`In-Reply-To` params on `resend.emails.send`).
  Resend does have a newer "Inboxes" API
  (`resend.inboxes.threads.emails.*`) that automates this, but it is
  explicitly early-access/preview only (`resend@6.28.1-preview-inboxes.1`,
  requires requesting access via resend.com/help) — do NOT build on
  top of this preview API for production; build Synkra's own
  threading as the founder's spec (#9) already anticipated.
- **Attachments and body are METADATA-ONLY in the webhook payload.**
  Confirmed directly from Resend's own webhook reference
  (resend.com/docs/webhooks/emails/received): "Webhooks do not include
  the email body, headers, or attachments, only their metadata. You
  must call the Received emails API or the Attachments API to retrieve
  them." So every inbound email needs a synchronous follow-up API call
  (`resend.emails.receiving.get(email_id)`) to get the actual body and
  attachment download URLs - this is a required second step, not
  optional.
- **Open/unverified**: how long attachment download URLs stay valid
  before expiring is not documented anywhere I found. Test this
  directly in a trial Resend account (send a test email with an
  attachment, fetch the download URL, wait, see when/if it expires)
  before relying on it in a background job with any processing delay -
  a slow Sidekiq queue could otherwise silently lose attachment data.
- All plans include: inbound emails, webhooks, DKIM/SPF/DMARC, SOC 2
  Type II, GDPR compliance - no inbound-specific gating by plan tier
  beyond the overall email-count quota.

## Decisions already made (confirmed directly by the founder this
session - do not re-ask)

1. **Resend account**: customer email-channel traffic will share
   Chat's EXISTING Resend account (the same one already configured for
   Chat's own system/transactional email - see
   `/areas/synkra-chat.md` memory for the SMTP setup from 21 Sep).
   Founder explicitly chose simplicity over isolation here, aware of
   the shared-quota/shared-rate-limit tradeoff above.
2. **Admin fallback/verification view**: build it as part of this
   feature (not deferred), but it belongs inside the EXISTING
   administrator-only area on account 3 (Synkra Technologies' own
   internal Chat account) where Student Programme and Community Access
   applications are already reviewed/approved/rejected (see
   `Billing::StudentVerificationsController`,
   `Billing::CommunityApplicationsController`, and whatever admin
   review UI already exists for those - check the current
   `synkra-main` state, since that review UI may have been built or
   extended by other sessions since this handover was written). This
   is explicitly ONLY for Synkra's own internal account/administrators
   - not a per-customer-visible feature. Its purpose: let Synkra staff
   see pending email-forwarding verification emails across customer
   accounts and click through to help a stuck customer complete
   verification, as a support/fallback tool.
3. **Explicitly NOT in scope for this handover's work**: anything
   about Student Programme or Community Access Programme review logic
   itself - the founder was clear "don't build anything regarding
   this" when clarifying decision #2, meaning don't touch/extend the
   existing student/community review system beyond placing the new
   email-verification-fallback view alongside it in the same
   admin-only area.

## Suggested starting points for the next session (not decided,
just pointers - the next session should still think this through
properly rather than treat this as a spec to blindly implement)

- Chatwoot already has a full native `Channel::Email` model (IMAP/SMTP
  based) - this new feature is NOT that. It's a fundamentally different
  model (forwarding-based, Resend-inbound-based, no customer
  credentials ever stored) and almost certainly needs its own new
  channel type or a variant, not a reuse of `Channel::Email` as-is.
  Worth deciding early whether this is a new `Channel::` subtype
  (fits Chatwoot's existing inbox/channel polymorphic pattern cleanly)
  or a bolt-on service sitting in front of the existing email channel.
- Will need at least: a model mapping the generated inbound address to
  a Chat inbox (per the founder's own stated DB relationship), a
  verification-state tracking concept (pending/forwarding-detected/
  verified/failed), a conversation-threading lookup keyed on
  Message-ID/In-Reply-To/References, and an attachment-fetching
  background job (given the required synchronous follow-up API call
  noted above).
- The existing `docs/synkra/resend-email-setup.md` doc (from the
  original SMTP setup) may be worth reviewing/extending alongside this
  new inbound-specific setup, to keep one coherent Resend
  configuration doc rather than two disconnected ones.
- Given Resend's own domain-verification/MX-record pattern recommends
  a dedicated subdomain when a root domain already has real mail
  service (exactly `synkra.co.za`'s situation, which already has real
  mail via whatever the founder's team uses for `hello@synkra.co.za`
  etc.), `inbound.synkra.co.za` as a dedicated subdomain for this is
  the right call and matches Resend's own documented best practice -
  no conflict expected with the domain's existing mail setup.

## Context this session also touched (unrelated to email inbox, for
awareness only)

This was an extremely long single session that also: fixed a CSRF bug
blocking community-access form submissions, fixed the free-email
("work email only") signup rejection, found and fixed a real bug where
an earlier session's `pricing_programme` method definition was
shadowing a real DB column used by the Student/Community billing
system (fixed by removing the method, not re-adding it), built a
shareable QR code / direct link feature for Website Widget inboxes,
and built a full ZAR/USD display-currency toggle for Chat's billing
settings page. None of that is related to this email feature, but
is worth knowing exists if cross-referencing recent git history.

Also note: multiple Claude sessions were working on this same repo
concurrently throughout today (this session repeatedly had to merge
with another session's concurrent pushes covering AI-ops/notification-
email billing, a Token Harbor LLM provider switch, and Captain/Copilot
fixes) - check `git log --oneline -30` on `synkra-main` for the full
current picture before assuming this doc is the only recent change.
