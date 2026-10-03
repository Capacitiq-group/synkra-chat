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
  via `Automations::SyncFlowPlanJob`, which flips the shadow user's `tier`
  and stamps `flow_plan_synced_at`.
- Two hourly sweeps self-heal jobs that exhausted their retries or never
  ran (process died mid-flight): `Automations::ReconcileFlowPlanJob`
  re-syncs any subscription where `plan_sync_stale?` is true (compares
  `flow_plan_synced_at` against the dedicated `plan_changed_at` column,
  deliberately not the generic `updated_at` — see the migration comment
  for why that would be racy), and `Automations::RetryStuckProvisioningJob`
  retries provisioning for any account still unprovisioned 2+ hours after
  creation. Both registered in `config/schedule.yml`.
- Ops-only key rotation/revocation lives in `lib/tasks/automations.rake` -
  no customer-facing equivalent, on purpose.

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
automatically. **Except:** `synkra-client-hub` already has a deploy-time
seeding script (`scripts/seed-pocketbase.mjs`) that applies the full
`pb_schema.json` (`collections` array + `userFields`) idempotently —
creating missing collections, adding missing fields/indexes, never
touching what already exists. Checked: it is NOT currently wired into any
CI/CD step in this repo (no package.json script, no workflow references
it) — it has to be run by hand. It also does two other things beyond
schema (touches the `SEED_OWNER_EMAIL` portal user's profile/password and
syncs workflow templates), so running it isn't schema-only — read the
script header before running in production:

```bash
cd synkra-client-hub
POCKETBASE_URL=https://pb.synkra.co.za \
PB_ADMIN_EMAIL=<existing superuser email> \
PB_ADMIN_PASSWORD=<existing superuser password> \
SEED_OWNER_PASSWORD=<the real owner password, or this run will overwrite it> \
node scripts/seed-pocketbase.mjs
```

## Env vars

- `CHAT_SHARED_SECRET` — must match exactly on both this app's deploy and
  synkra-core's. High-entropy random string, not reused from any other
  secret.
- `FLOW_API_BASE_URL` — defaults to `https://api.synkra.co.za`.

## Known gaps (as of 13 Sep 2026, not yet deployed)

- No tests for the Python side (`synkra-core`) — the Ruby side now has
  specs (`spec/services/automations/`, `spec/jobs/automations/`,
  `spec/models/synkra_subscription_spec.rb`,
  `spec/requests/api/v1/accounts/automations/`), but `synkra-core` has
  zero test infrastructure of any kind (not just for this feature) —
  introducing pytest there is a separate decision, not made yet.
- Key rotation/revocation is ops-only (`lib/tasks/automations.rake`) —
  no customer-facing UI, deliberately, since a business managing its own
  Flow API key would undercut the "Automations" framing.
- The `CHAT_SHARED_SECRET` env var still needs generating and setting on
  both deploys (matching exactly) before any of this works.
- The two PocketBase collections still need applying — see the
  `seed-pocketbase.mjs` command above.
