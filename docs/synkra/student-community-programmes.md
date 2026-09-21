# Student and Community Access programmes

Branch: `feat/student-community-access`. Discounts change only the price, never the plan limits.

## Environment variables (add to each Coolify service, and to the compose `environment:` block the same way the existing PAYSTACK_PLAN_CODE_* vars are)

| Variable | Purpose |
|---|---|
| `PAYSTACK_PLAN_CODE_STARTER_STUDENT`, `_BUSINESS_STUDENT`, `_PRO_STUDENT` | Paystack plans at R195 / R389 / R649 |
| `PAYSTACK_PLAN_CODE_STARTER_COMMUNITY`, `_BUSINESS_COMMUNITY`, `_PRO_COMMUNITY` | Paystack plans at R119 / R239 / R399 |
| `KIMI_API_KEY` | Reads student documents. Without it every document goes to manual review |
| `KIMI_MODEL` (optional) | Defaults to `kimi-k2.6` |
| `KIMI_API_BASE_URL` (optional) | Defaults to `https://api.moonshot.ai/v1` |
| `PROGRAMME_REVIEW_EMAIL` | Where "new application waiting" emails go. Unset = no email, use the queue |

Plan codes exist in ONE Paystack mode only (test or live) - staging and production each need their own six.

## Where things are
- Applicants: Settings > Billing > "Student discount" and "Community Access".
- Reviewers: Super Admin > "Programme reviews" (approve / request more info / reject, each emails the applicant).
- Daily job `Billing::ExpireProgrammesJob` (02:15): warns at 30 and 7 days, then moves lapsed accounts to Free.

## Rules
- Student: 35% off. Verified by institution email code or a document. Lasts until 31 Dec (SA time).
- Community: 60% off. Manual review. Lasts 12 months from approval.
- Never auto-rejected: anything the automatic document check is unsure about goes to the review queue.
- Expired = Free tier, never the standard price.
