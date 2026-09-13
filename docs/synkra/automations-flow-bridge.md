# Automations (Chat ↔ Flow bridge)

Started 12 Sep 2026. Gives Synkra Chat businesses Flow's AI-ops/email
credit metering, scoped to chat, without ever making them Flow customers.

**User-facing name: "Automations".** Never call this "Flow", "Connect to
Flow", or anything that implies the business is getting a reduced or
lesser version of a separate product. A business that wants full Flow
signs up for Flow separately and deliberately — this bridge has nothing
to do with that decision either way.

## Why this exists

Two requirements drove the design (Refilwe, 12 Sep 2026):

1. One unified AI-ops/email credit balance shared between Chat and Flow —
   unused capacity on one side shouldn't be wasted because it's siloed
   from the other.
2. Chat businesses get Flow capabilities *scoped to chat* — not the whole
   of Flow (not arbitrary third-party integrations like Google Sheets) —
   and critically, **never have to create a Flow account**. Two-platform
   users was explicitly rejected.

## How it works

- On Chat account creation (`Account#provision_synkra_subscription`),
  `Automations::ProvisionFlowJob` calls Flow's
  `POST /internal/chat-accounts/provision` server-to-server, authenticated
  by the `CHAT_SHARED_SECRET` env var (shared only between this app and
  `synkra-core` — deliberately not the same secret client-hub uses for its
  own internal routes).
- Flow creates a real row in its own `users` collection for the business —
  unusable password, never a login a human can reach — and mints a
  `SYN_...` API key scoped to that row. This is the "shadow client".
  Because it's a real `users` row, it draws on the exact same
  `consume_credit()` metering (included allowance → FIFO purchased
  add-ons) that a genuine Flow customer uses. **One balance, not a second
  pool.**
- Chat stores the returned key encrypted on
  `SynkraSubscription#flow_api_key` (`encrypts :flow_api_key if
  Chatwoot.encryption_configured?`). It is never shown to the business.
- `Automations::FlowClient` is the only thing that ever uses this key —
  reads credit usage (`GET /api/v1/credits`, surfaced read-only via
  `Api::V1::Accounts::Automations::CreditsController`), consumes credit
  (`POST /api/v1/credits/consume`), and can trigger chat-relevant Flow
  workflows (`POST /api/v1/workflows/{id}/trigger`) — all scoped to that
  one business's shadow user, nothing else in Flow.
- Plan changes (`SynkraSubscription#change_plan!` /
  `#apply_pending_plan_change!`) push the new plan to Flow asynchronously
  via `Automations::SyncFlowPlanJob`, which flips the shadow user's `tier`.

## Tier mapping

Flow only has three tiers; Chat has four:

| Chat plan | Flow tier |
|---|---|
| Free | `free` (pay-as-you-go — 0 included AI-ops, 300 included emails; add-on credits required for AI-ops) |
| Starter | `basic` |
| Business | `basic` |
| Pro | `pro` |

Any Chat plan, including Free, can buy add-on credit packs — FIFO, exactly
as Flow's existing `addon_credits` mechanism already works. Nothing about
that mechanism changes for this bridge.

## PocketBase schema

Declared in `synkra-client-hub/pb_schema.json` (the canonical schema) and
documented in `synkra-client-hub/POCKETBASE_COLLECTIONS.md`:

- `flow_shadow_clients` — identity mapping only (`chat_account_id` ↔
  `flow_user_id`), never a balance.
- `chat_api_keys` — one shadow client can hold multiple `SYN_...` keys,
  independently revocable. Only the sha256 hash is stored.
- `users.source` (new select field: `signup` | `chat_shadow`) — marks
  which `users` rows are real Flow signups vs. Chat-provisioned shadow
  rows.

These collections must be created by hand in the PocketBase admin
(`pb.synkra.co.za`) — there's no migration tooling for PocketBase in this
stack; `pb_schema.json` is the reference, not something applied
automatically.

## Env vars

- `CHAT_SHARED_SECRET` — must match exactly on both this app's deploy and
  synkra-core's. High-entropy random string, not reused from any other
  secret.
- `FLOW_API_BASE_URL` — defaults to `https://api.synkra.co.za`.

## Known gaps (as of 12 Sep 2026, not yet deployed)

- No periodic reconciliation sweep if `Automations::SyncFlowPlanJob`
  exhausts its retries — a permanently failed plan sync stays stale until
  the next plan change touches that account. Worth building if this turns
  out not to be rare in practice.
- The credits endpoint's frontend UI (an actual "Automations" tab a
  business sees) hasn't been built yet — only the backend
  (`Api::V1::Accounts::Automations::CreditsController`) exists so far.
- No tests written yet for any of `Automations::*`.
- Whether a business can request an additional key or needs to revoke one
  is currently only exposed via `synkra-core`'s internal
  (`/internal/chat-accounts/{id}/keys`) endpoints — no Chat-side UI or
  route calls them yet.
