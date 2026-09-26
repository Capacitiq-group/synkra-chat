# Deployment runbook: checkout fix, Student and Community Access programmes

Code: branch `feat/student-community-access` (fast-forwards onto `synkra-main`; three additive migrations).
Order: prepare Paystack + env vars -> deploy staging from the branch -> test -> merge -> deploy production from `synkra-main`.

## Part 1. Prepare (once per environment)

1. Paystack dashboard: change "Chat - Starter STU" from R199 to R195 (keep the plan code).
2. Plan codes only exist in the Paystack mode they were created in (test OR live). Staging needs the six programme plans in TEST mode, production in LIVE mode.
3. Check which mode each server's key is in (prints 8 characters, `sk_test_` or `sk_live_`):
   docker exec <rails-container> printenv PAYSTACK_SECRET_KEY | cut -c1-8
4. See how the existing plan codes are wired into the compose file, and copy that pattern:
   grep -n "PAYSTACK_PLAN_CODE" /data/coolify/services/<service-id>/docker-compose.yml
   Add these to BOTH the rails and sidekiq services (sidekiq runs the document review, emails and the daily expiry job), and to the service's Environment Variables in Coolify:
   PAYSTACK_PLAN_CODE_STARTER_STUDENT, PAYSTACK_PLAN_CODE_BUSINESS_STUDENT, PAYSTACK_PLAN_CODE_PRO_STUDENT,
   PAYSTACK_PLAN_CODE_STARTER_COMMUNITY, PAYSTACK_PLAN_CODE_BUSINESS_COMMUNITY, PAYSTACK_PLAN_CODE_PRO_COMMUNITY,
   KIMI_API_KEY, PROGRAMME_REVIEW_EMAIL (and optionally KIMI_MODEL).
5. Confirm they reached the files on disk:
   grep -c "STUDENT\|COMMUNITY\|KIMI\|PROGRAMME_REVIEW" /data/coolify/services/<service-id>/docker-compose.yml /data/coolify/services/<service-id>/.env

## Part 2. Deploy staging (service tdrusxbd5khg1vyjcd4gdevv)

cd /opt/synkra-chat-dev
git fetch origin
git checkout feat/student-community-access
git pull
(then your staging script from `docker build` down)

## Part 3. Verify staging

git -C /opt/synkra-chat-dev log --oneline -1
docker exec rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rails db:migrate:status | tail -4      # 3 new migrations "up"
docker exec rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rails runner "p SynkraPlan.for_programme('starter','student').slice(:price_zar,:paystack_plan_code); p Billing::KimiClient.new.configured?; p Sidekiq::Cron::Job.all.map(&:name).grep(/programme/)"

Expect: price 195 with a PLN_ code, true, and ["synkra_expire_programmes_job"].

## Part 4. Test on staging (in order; stop at the first failure)

1. Paid checkout: new signup at /app/auth/signup?plan=starter, verify email, log in, pay with a Paystack test card. Expect the billing page to show Chat Starter / active within ~20 seconds.
2. Student email: Settings > Billing > Student discount. Number, institution, ending, send code, enter it. Expect "Verified student until 31 Dec". Plan cards show student prices.
3. Student price at checkout: on a fresh Free account verify as a student, upgrade to Starter. Paystack must show R195. Afterwards pricing_programme = student.
4. Already paying, then verifies: on the account from test 1, verify as a student. Expect pricing_programme = student and a new paystack_subscription_code (moved from next billing date).
5. Document: fresh account, "Verify with a document instead", upload a real registration document in your own name. Expect approval within minutes, or a row in Super Admin > Programme reviews.
6. Community: apply from Settings > Billing, then approve it in Super Admin > Programme reviews. Expect the email and community prices.
7. Expiry: set a student verification's expires_at to the past, run Billing::ExpireProgrammesJob.perform_now. Expect that account on Free with no Paystack subscription.

Inspect an account after any step:
docker exec rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rails runner "p SynkraSubscription.find_by(account_id: X).slice(:plan,:status,:pricing_programme,:paystack_customer_code,:paystack_subscription_code)"

## Part 5. Merge, then production (service 0ojl8fw19lens2ifijutg4od)

Merge `feat/student-community-access` into `synkra-main` (fast-forward). Then on production repeat Parts 1 (live mode), 2 and 3 using /opt/synkra-chat-prod, `synkra-main` and the production script. Test with one live payment at the cheapest programme price and refund it in Paystack.

## Rollback

Migrations only add tables/columns, so rolling back code is safe: check out `synkra-main` (or the previous commit), rebuild, redeploy. No database rollback needed.
