# Deployment Runbook v2 — Full Session (15 Sep 2026)

Supersedes `deployment-runbook-2026-09-14.md`. Covers everything on
`synkra-main` from the first Automations-bridge commit through the
most recent (Chat-local AI-ops/email tracking). If nothing from this
session has been deployed yet, this is the complete picture — deploy
once, not in pieces.

**Read fully before starting.** This touches real billing/Paystack
logic. Confirm each step's output before moving to the next.

---

## PRE-DEPLOYMENT

### 1. Env vars to set

| Var | Value | Why |
|---|---|---|
| `CHAT_SHARED_SECRET` | high-entropy random string, matching synkra-core's value exactly | Automations bridge auth (currently dormant since Automations is hidden, but should still be set correctly for when Flow relaunches) |
| `PAYSTACK_SECRET_KEY` | your Paystack secret key | Already required for existing billing - confirm it's actually set |
| `SMTP_ADDRESS` / `SMTP_PORT` / `SMTP_USERNAME` / `SMTP_PASSWORD` | Resend's SMTP relay values - see `docs/synkra/resend-email-setup.md` | Outbound email |

### 2. What NOT to worry about this time

- **PocketBase collections** (`flow_shadow_clients`, `chat_api_keys`) - not urgent. The Automations bridge that needs them is hidden behind a `false &&` guard in the sidebar, and every backend call in that path fails open silently. You can still create them later using the schema from the earlier runbook if/when Flow relaunches.

### 3. Know what's changing before it changes

- **Message and seat limits go live for real** at these numbers: Free 250msg/1 seat, Starter 3,000/7, Business 8,000/15, Pro 25,000/50. If any real account is already over these, they'll be blocked from sending/adding seats the moment this deploys.
- **The Automations sidebar tab disappears.** This is intentional (Flow isn't launching soon) - don't be alarmed if a tester asks where it went.
- **A new "Send test email" capability exists** (`rake mailer:send_test`) - use it post-deploy to confirm Resend is actually working, since that's never been verified live.
- **AI-ops/email usage meters appear on the Billing page** - "Emails" will show 0 used regardless of actual activity (that recording hook isn't wired yet - tracking exists, the trigger doesn't).

---

## DEPLOYMENT

Same sequence as always:

```bash
cd /opt/synkra-chat-dev
git pull origin synkra-main
git log -1 --oneline   # should show the Chat-local AI-ops/email tracking merge as HEAD

docker build -f docker/Dockerfile -t synkra-chat:staging . 2>&1 | tee /tmp/synkra-build-$(date +%s).log

docker stop rails-tdrusxbd5khg1vyjcd4gdevv sidekiq-tdrusxbd5khg1vyjcd4gdevv 2>/dev/null
docker rm rails-tdrusxbd5khg1vyjcd4gdevv sidekiq-tdrusxbd5khg1vyjcd4gdevv 2>/dev/null
docker volume rm tdrusxbd5khg1vyjcd4gdevv_public-data   # frontend assets changed extensively this session

docker compose -f /data/coolify/services/tdrusxbd5khg1vyjcd4gdevv/docker-compose.yml --env-file /data/coolify/services/tdrusxbd5khg1vyjcd4gdevv/.env up -d rails
sleep 15
docker compose -f /data/coolify/services/tdrusxbd5khg1vyjcd4gdevv/docker-compose.yml --env-file /data/coolify/services/tdrusxbd5khg1vyjcd4gdevv/.env up -d sidekiq

docker exec -it rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rails db:migrate
```

Expect exactly these 7 migrations:
```
20260912100000_add_flow_automations_to_synkra_subscriptions.rb
20260913090000_add_flow_plan_synced_at_to_synkra_subscriptions.rb
20260913140000_create_message_addon_purchases.rb
20260913150000_add_purchased_extra_seats_to_synkra_subscriptions.rb
20260913160000_add_extra_seats_billed_for_reference_to_synkra_subscriptions.rb
20260914080000_add_storage_usage_to_synkra_subscriptions.rb
20260914090000_add_marketing_opt_in_to_users_and_contacts.rb
```
All additive (new columns/tables), nothing destructive. A different
list means the wrong commit is checked out - stop and check `git log`.

```bash
docker exec -it rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rails runner "ConfigLoader.new.process(reconcile_only_new: false)"

# Catch up any account that got hit by the pre-fix feature-stripping bug
docker exec -it rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rake accounts:check_premium_features
docker exec -it rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rake accounts:reconcile_premium_features
```

---

## POST-DEPLOYMENT

### 1. Confirm scheduled jobs loaded

```bash
docker exec -it sidekiq-tdrusxbd5khg1vyjcd4gdevv bundle exec rails runner "puts Sidekiq::Cron::Job.all.map(&:name)"
```
Should include `automations_reconcile_flow_plan_job`,
`automations_retry_stuck_provisioning_job`,
`billing_recalculate_storage_usage_job`, alongside the pre-existing
`synkra_billing_grace_period_job`.

### 2. Verify email actually works

```bash
docker exec -it rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rake mailer:config_check
docker exec -it rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rake mailer:send_test[you@example.com]
```

### 3. Confirm the AI Agent is actually visible

After the `reconcile_premium_features` task above, log in as a real
account and check Settings → AI Agent is there and usable. This was
very likely broken before this fix.

### 4. Smoke test message/seat enforcement

Push a test account near its message/seat limit and confirm blocking
kicks in with a clear error, not a 500.

### 5. First-time checkout — test before sending real traffic to it

```
https://chat.synkra.co.za/app/auth/signup?plan=starter
```
Sign up fresh, confirm it redirects straight to Paystack checkout for
Starter rather than landing on Free. Test `business` and `pro` too.

### 6. Paystack — you were already mid-testing this

The "cardholder not authorised" / "authentication failed" errors you
hit are almost certainly Paystack's own failure-simulating test cards,
not a bug (checkout init, webhook receiving, and signature
verification were all reviewed and are correct). Confirm with a real
card as planned. While testing, also check:
- Message add-on purchase credits the right amount, once
- Extra seats grant free immediately, first real charge only at next
  renewal
- Storage overage and extra-seat renewal charges never double-fire on
  a redelivered webhook (Paystack's dashboard may let you manually
  resend an event to test this)

### 7. Midnight UTC check

Same as every deploy - confirm feature flags and branding are still
intact after the first midnight UTC post-deploy.

### 8. Watch logs for

- `[SynkraBilling] Extra-seat renewal charge failed...`
- `[SynkraBilling] Storage overage renewal charge failed...`
- `[SynkraBilling] Failed to record ai_request usage event...`
- `Automations::ProvisionFlowJob failed...` (expected/harmless now -
  Flow is unreachable by design, these should just retry and give up
  quietly)

---

## Known limitations going in

- Email usage tracking exists but nothing increments it yet (always
  shows 0) - needs a decision on what should count as "one email"
  before that gets wired.
- Storage overage bills automatically rather than blocking uploads -
  a default choice, not an explicit decision from you.
- No proration for extra seats bought mid-period (moot for now since
  billing is deferred to the next renewal regardless).
- "Trigger a Flow" AI Agent action still points at a URL that assumes
  Flow is reachable - it isn't right now. Anyone who configures that
  action will find it doesn't work. Worth hiding that specific action
  type too, similar to how the Automations tab is hidden - not done
  yet, flagging it now since it only became obvious while writing
  this runbook.
