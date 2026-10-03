# Deployment Runbook — Chat↔Flow Automations, Billing Enforcement, Storage (14 Sep 2026)

Covers everything built since the last confirmed-live deploy: the full
Chat↔Flow "Automations" bridge, message/seat enforcement going live
for real, message add-on packs, extra seats, and storage usage
tracking. Three repos, deployed in a specific order because later
pieces depend on earlier ones being up first.

**Read this whole document before starting.** Confirm each step's
output before moving to the next — this deploy touches billing logic
that moves real money (Paystack charges), so a failure caught early is
cheap and a failure caught late is a support ticket or a refund.

---

## Deploy order (do not reorder)

1. **synkra-client-hub** (PocketBase schema) — the two new PocketBase
   collections must exist before synkra-core's provisioning endpoint
   can write to them.
2. **synkra-core** (Flow backend) — the Automations API must be live
   and reachable before synkra-chat tries to call it.
3. **synkra-chat** (Chat/Rails) — last, since it's the one calling out
   to the other two.

If synkra-chat deploys before synkra-core is reachable, nothing
breaks catastrophically — `Automations::ProvisionFlowJob` retries with
backoff and then gets picked up again by
`Automations::RetryStuckProvisioningJob`'s hourly sweep. But do it in
order anyway; there's no reason not to.

---

## PRE-DEPLOYMENT

### 1. Generate and set `CHAT_SHARED_SECRET`

This is the one secret nothing in this session had credentials to set.
It must be the **exact same value** on both synkra-core's and
synkra-chat's environments — it's how Chat's backend authenticates to
Flow's internal provisioning endpoints (`/internal/chat-accounts/...`).

A value was already generated for you earlier in this conversation.
If you've lost it, generate a fresh one:

```bash
python3 -c "import secrets; print(secrets.token_urlsafe(48))"
```

Set it as `CHAT_SHARED_SECRET` in:
- synkra-core's environment (wherever that's deployed — not detailed
  in this runbook since this session never had access to synkra-core's
  deploy specifics beyond its repo)
- synkra-chat's Coolify env file:
  `/data/coolify/services/tdrusxbd5khg1vyjcd4gdevv/.env`

### 2. Confirm `FLOW_API_BASE_URL`

Defaults to `https://api.synkra.co.za` in
`Automations::FlowClient` if unset (this matches
`synkra-client-hub/.env.example`'s own `API_URL`, so it's very likely
already correct) — but confirm this is genuinely where synkra-core is
reachable in production before relying on the default silently doing
the right thing. Set `FLOW_API_BASE_URL` explicitly in synkra-chat's
env if there's any doubt.

### 3. Apply the PocketBase schema

Creates `flow_shadow_clients`, `chat_api_keys`, and the `users.source`
field. `synkra-client-hub` already has an idempotent seeding script for
this — **read its side effects before running** (it also touches an
owner-account password, see the caveat below):

```bash
cd synkra-client-hub
POCKETBASE_URL=https://pb.synkra.co.za \
PB_ADMIN_EMAIL=<existing superuser email> \
PB_ADMIN_PASSWORD=<existing superuser password> \
SEED_OWNER_PASSWORD=<the real owner password, or this run overwrites it> \
node scripts/seed-pocketbase.mjs
```

Safe to re-run — collections/fields are only ever added, never
removed or altered. Verify in the PocketBase admin
(`pb.synkra.co.za`) afterward that `flow_shadow_clients` and
`chat_api_keys` both exist, and that `users` has a `source` field.

### 4. Review what's about to go live (read, don't skip)

This batch makes several things **real** that were previously
placeholders or inert:

- **Message and seat limits will actually enforce.** Free 250
  messages/1 seat, Starter 3000/7, Business 8000/15, Pro 25000/50 —
  these are confirmed-final numbers, not placeholders, and
  `Message#enforce_synkra_billing_restriction` /
  `AccountUser#ensure_within_synkra_seat_limit` will start blocking
  once a business hits them. If any currently-live business is already
  over these numbers, they will be blocked from sending outbound
  messages or adding seats the moment this deploys. **Worth checking
  current usage against these numbers before deploying**, if any real
  customers exist yet.
- **Recurring Paystack charges will start firing automatically** at
  plan renewal for: extra seats (if any exist — none should, since
  this is the first deploy of the feature) and storage overage (same).
  Both are genuinely new code paths that have never run against a
  real Paystack transaction. See the "Live verification" section
  below — do this before any real customer's card is on the line.

---

## DEPLOYMENT

Same sequence as your existing runbook (nothing about *how* you deploy
changes, only *what's* in this deploy):

```bash
# PRE
cd /opt/synkra-chat-dev
git pull origin synkra-main
git log -1 --oneline   # should show the storage-usage-tracking merge as HEAD

# BUILD
docker build -f docker/Dockerfile -t synkra-chat:staging . 2>&1 | tee /tmp/synkra-build-$(date +%s).log

# RECREATE
docker stop rails-tdrusxbd5khg1vyjcd4gdevv sidekiq-tdrusxbd5khg1vyjcd4gdevv 2>/dev/null
docker rm rails-tdrusxbd5khg1vyjcd4gdevv sidekiq-tdrusxbd5khg1vyjcd4gdevv 2>/dev/null
docker volume rm tdrusxbd5khg1vyjcd4gdevv_public-data   # only if frontend assets changed - they did (new Automations tab, updated Billing page)

docker compose -f /data/coolify/services/tdrusxbd5khg1vyjcd4gdevv/docker-compose.yml --env-file /data/coolify/services/tdrusxbd5khg1vyjcd4gdevv/.env up -d rails
sleep 15
docker compose -f /data/coolify/services/tdrusxbd5khg1vyjcd4gdevv/docker-compose.yml --env-file /data/coolify/services/tdrusxbd5khg1vyjcd4gdevv/.env up -d sidekiq

# MIGRATE — 6 new migrations, all additive (new columns/tables only, nothing destructive)
docker exec -it rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rails db:migrate
```

Expect these 6 migrations to run:
```
20260912100000_add_flow_automations_to_synkra_subscriptions.rb
20260913090000_add_flow_plan_synced_at_to_synkra_subscriptions.rb
20260913140000_create_message_addon_purchases.rb
20260913150000_add_purchased_extra_seats_to_synkra_subscriptions.rb
20260913160000_add_extra_seats_billed_for_reference_to_synkra_subscriptions.rb
20260914080000_add_storage_usage_to_synkra_subscriptions.rb
```

If you see a different set (more, fewer, or different names), stop and
check `git log -1 --oneline` matches what you expect before continuing
— a mismatch means the wrong commit is checked out.

```bash
# POST
docker exec -it rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rails runner "ConfigLoader.new.process(reconcile_only_new: false)"
```

### New scheduled jobs — confirm they loaded

This deploy adds four new hourly/daily Sidekiq-cron jobs
(`automations_reconcile_flow_plan_job`,
`automations_retry_stuck_provisioning_job`,
`billing_recalculate_storage_usage_job`, plus reuses the existing
hourly slot pattern). These load automatically from
`config/schedule.yml` when the sidekiq container starts — no separate
action needed, but confirm they actually registered:

```bash
docker exec -it sidekiq-tdrusxbd5khg1vyjcd4gdevv bundle exec rails runner "puts Sidekiq::Cron::Job.all.map(&:name)"
```

Should include: `automations_reconcile_flow_plan_job`,
`automations_retry_stuck_provisioning_job`,
`billing_recalculate_storage_usage_job`, alongside the pre-existing
`synkra_billing_grace_period_job`.

---

## POST-DEPLOYMENT

### 1. Smoke test — Automations provisioning

Create a fresh test account (or use an existing test one) and confirm
a shadow Flow client gets provisioned:

```bash
docker exec -it rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rails runner "
  account = Account.find(<test_account_id>)
  sleep 5 # ProvisionFlowJob is async
  sub = account.synkra_subscription
  puts sub.flow_api_key.present? ? 'PROVISIONED' : 'NOT YET - check sidekiq logs'
"
```

Also check the "Automations" tab in that account's Settings sidebar —
should move from "setting up" to showing a usage summary within a few
seconds.

### 2. Smoke test — message/seat enforcement

On a test account, manually set `business_initiated_message_allowance`
usage near the limit (or use the real Free tier's low 250 number) and
confirm sending is blocked with the expected error message, not a
500 or a silent failure. Same for seats — try adding a teammate past
the limit.

### 3. Live-test the money-moving paths — do this before any real customer touches them

None of the following has ever run against a real Paystack
transaction. This is the single most important thing in this whole
runbook:

- **Message add-on purchase**: buy the smallest pack (R50 → 5,000)
  on a test account with a real (test-mode) card, confirm the
  webhook lands and `purchased_message_credits` increments by exactly
  5,000 — not zero, not double.
- **Extra seats**: purchase seats, confirm they're granted immediately
  with **no charge** (this is the deferred-billing behavior). Then
  either wait for or manually trigger a plan renewal
  (`Billing::PaystackWebhookHandler` processing a `charge.success`
  webhook for that subscription) and confirm **exactly one** charge
  for `seats × R69` appears — not zero, not two.
- **Storage overage**: get a test account's cached `storage_used_mb`
  over its plan allowance (can force this via
  `subscription.update_column(:storage_used_mb, ...)` for testing),
  trigger a renewal, confirm exactly one charge for
  `overage_gb × R30` appears.
- **Redelivery safety**: if Paystack's dashboard lets you manually
  resend a webhook event, do it for one of the above and confirm
  nothing gets charged twice. This is the specific thing the
  `extra_seats_billed_for_reference` / `storage_overage_billed_for_reference`
  columns exist to guarantee — worth actually seeing it hold.

### 4. Check the AI Agent still replies (consumption tracking)

Send a message that triggers a Synkra AI Agent (Captain) reply on a
test account, then confirm `automations_credits`'s `ai_ops.used` went
up by 1 via the Automations tab or `subscription.automations_credits`.
Confirm the reply itself wasn't delayed or affected — this tracking is
supposed to be invisible from the customer's side.

### 5. Midnight UTC check (recurring, not just for this deploy)

Per the existing known issue: `Enterprise::Internal::CheckNewVersionsJob`
runs daily at midnight UTC and previously stripped premium features and
branding — confirmed fixed in commit `63aa3c6f3`, but worth re-checking
after this deploy's first midnight UTC that both feature flags and
branding are still intact, same as any other deploy.

### 6. Watch error logs for the first 24-48h, specifically for:

- `[SynkraBilling] Extra-seat renewal charge failed for account ...`
- `[SynkraBilling] Storage overage renewal charge failed for account ...`
- `[SynkraBilling] Failed to recalculate storage usage for account ...`
- `Automations::ProvisionFlowJob failed for account ...`
- `Automations::SyncFlowPlanJob failed for account ...`

All of the above fail open (never block the business), so a spike in
any of these is a signal to investigate, not an outage.

---

## Known limitations going into this deploy (not blockers, just things to know)

- **Storage overage does not block uploads** — bills automatically
  instead, unlike messages/seats which do block. This was a default
  choice, not an explicit decision from you — flagged in
  `SynkraSubscription#bill_storage_overage_for_renewal!`'s comment.
- **"Trigger a Flow" AI Agent actions still bypass the whole
  Automations bridge** — they call Flow's raw unauthenticated
  webhook URL directly. Not touched in this batch; needs its own
  design work.
- **No dunning/retry for failed extra-seat or storage-overage
  charges** — a permanently failing card just keeps granting the
  seats/storage silently. The base plan has
  `Billing::RestrictOverdueSubscriptionsJob` for this; extra
  seats/storage don't have an equivalent yet.
- **No proration for extra seats bought mid-period** — moot now,
  since seats are billed at the next renewal regardless (deferred,
  not prorated) — mentioned here only so it's not mistaken for an
  oversight.
- **synkra-core has zero test coverage** of any kind, for this feature
  or anything else — a separate, unmade decision about whether to
  introduce pytest there.
