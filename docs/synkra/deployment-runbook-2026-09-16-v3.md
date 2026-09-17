# Deployment Runbook v3 — Final, Full Session (16 Sep 2026)

Supersedes v2. Adds two commits since then: hiding the AI Agent Actions
tab (all five presets are Flow-dependent) + wiring email usage
tracking, and doc corrections. No new migrations — still 7 total.

---

## PRE-DEPLOYMENT

**Env vars:**
| Var | Value |
|---|---|
| `CHAT_SHARED_SECRET` | high-entropy random string, matches synkra-core (dormant while Automations is hidden) |
| `PAYSTACK_SECRET_KEY` | confirm it's set |
| `SMTP_ADDRESS`/`PORT`/`USERNAME`/`PASSWORD` | Resend's SMTP relay values |

**Not urgent:** PocketBase collections — bridge is hidden, fails open.

**Know before it lands:**
- Message/seat limits go fully live: Free 250msg/1seat, Starter 3,000/7, Business 8,000/15, Pro 25,000/50
- Automations tab AND AI Agent Actions tab both disappear (intentional — Flow isn't launching soon)
- Emails meter now actually increments (1 email = 1 message sent through an Email-channel inbox)
- AI-ops numbers: Free 0, Starter 1,000, Business 1,750, Pro 1,750 (temporary Chat-local tracking, independent of Flow)

---

## DEPLOYMENT

```bash
cd /opt/synkra-chat-dev
git pull origin synkra-main
git log -1 --oneline   # should show the doc-corrections merge as HEAD

docker build -f docker/Dockerfile -t synkra-chat:staging . 2>&1 | tee /tmp/synkra-build-$(date +%s).log

docker stop rails-tdrusxbd5khg1vyjcd4gdevv sidekiq-tdrusxbd5khg1vyjcd4gdevv 2>/dev/null
docker rm rails-tdrusxbd5khg1vyjcd4gdevv sidekiq-tdrusxbd5khg1vyjcd4gdevv 2>/dev/null
docker volume rm tdrusxbd5khg1vyjcd4gdevv_public-data

docker compose -f /data/coolify/services/tdrusxbd5khg1vyjcd4gdevv/docker-compose.yml --env-file /data/coolify/services/tdrusxbd5khg1vyjcd4gdevv/.env up -d rails
sleep 15
docker compose -f /data/coolify/services/tdrusxbd5khg1vyjcd4gdevv/docker-compose.yml --env-file /data/coolify/services/tdrusxbd5khg1vyjcd4gdevv/.env up -d sidekiq

docker exec -it rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rails db:migrate
```

Expect exactly 7 migrations:
```
20260912100000_add_flow_automations_to_synkra_subscriptions.rb
20260913090000_add_flow_plan_synced_at_to_synkra_subscriptions.rb
20260913140000_create_message_addon_purchases.rb
20260913150000_add_purchased_extra_seats_to_synkra_subscriptions.rb
20260913160000_add_extra_seats_billed_for_reference_to_synkra_subscriptions.rb
20260914080000_add_storage_usage_to_synkra_subscriptions.rb
20260914090000_add_marketing_opt_in_to_users_and_contacts.rb
```

```bash
docker exec -it rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rails runner "ConfigLoader.new.process(reconcile_only_new: false)"
docker exec -it rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rake accounts:check_premium_features
docker exec -it rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rake accounts:reconcile_premium_features
```

---

## POST-DEPLOYMENT

1. **Scheduled jobs**: `docker exec -it sidekiq-tdrusxbd5khg1vyjcd4gdevv bundle exec rails runner "puts Sidekiq::Cron::Job.all.map(&:name)"` — should list `automations_reconcile_flow_plan_job`, `automations_retry_stuck_provisioning_job`, `billing_recalculate_storage_usage_job`, `synkra_billing_grace_period_job`
2. **Email**: `rake mailer:config_check` then `rake mailer:send_test[you@example.com]`
3. **AI Agent visible**: Settings → AI Agent should be there after the reconcile task
4. **Message/seat blocking**: push a test account near its limit
5. **Checkout**: `https://chat.synkra.co.za/app/auth/signup?plan=starter` → should redirect straight to Paystack
6. **Paystack real-card test**: your next step. Also check message add-on credit amount, seat deferral (no charge at purchase, first charge at renewal), no double-charge on a redelivered webhook
7. **Email tracking**: send a message through an Email-channel inbox, confirm the emails meter on Settings → Billing increments by 1
8. **Midnight UTC check**: confirm feature flags/branding intact after
9. **Watch logs** for `[SynkraBilling] ... failed`, `Automations::ProvisionFlowJob failed` (expected/harmless — Flow unreachable by design)

---

## Known limitations going in

- Storage overage bills automatically rather than blocking (default choice, not explicitly decided)
- No proration for extra seats (moot — billing deferred to next renewal regardless)
- AI Agent Actions (Trigger a Flow, Send email action, Create lead, Book appointment, Create order) all hidden — rebuilding these to not depend on Flow is future work, not started
- synkra-core has zero test coverage (separate, unmade decision)
