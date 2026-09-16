import SynkraBillingAPI from 'dashboard/api/synkraBilling';

// "Chat first-time checkout" (Refilwe, 15 Sep 2026): a visitor picks a
// plan on the marketing site, lands on Chat's signup page via
// ?plan=<key>, and the actual Paystack checkout happens once they
// first reach the dashboard - not on the marketing site itself, and
// not by defaulting them onto Free and making them find billing
// settings themselves.
//
// Uses localStorage rather than threading a query param through
// signup -> verify-email -> login (three separate pages, an email
// click in between two of them) - a query param would need every one
// of those pages and redirects to deliberately preserve and re-emit
// it, and an email verification link is generated server-side without
// any way to carry a frontend-only param through it anyway.
// localStorage survives all of that with no extra plumbing.
const STORAGE_KEY = 'synkra_pending_checkout_plan';
const VALID_PLANS = ['starter', 'business', 'pro']; // never 'free' - nothing to check out for that

export function capturePendingPlanFromQuery(query) {
  const plan = query?.plan;
  if (VALID_PLANS.includes(plan)) {
    localStorage.setItem(STORAGE_KEY, plan);
  }
}

export function getPendingPlan() {
  const plan = localStorage.getItem(STORAGE_KEY);
  return VALID_PLANS.includes(plan) ? plan : null;
}

export function clearPendingPlan() {
  localStorage.removeItem(STORAGE_KEY);
}

// Redirects the browser to Paystack checkout if - and only if - a
// plan intent is waiting. Clears the intent before redirecting so a
// user who navigates back mid-checkout and reloads doesn't get
// checkout re-triggered in a loop. Never throws - if the checkout
// call itself fails, the user just lands on their (free) dashboard
// normally, same as if they'd never picked a plan; they can still
// upgrade manually from Settings -> Billing.
export async function redeemPendingPlanCheckout(accountId) {
  const plan = getPendingPlan();
  if (!plan || !accountId) return;

  clearPendingPlan();

  try {
    const callbackUrl = `${window.location.origin}/app/accounts/${accountId}/settings/billing`;
    const response = await SynkraBillingAPI.checkout(plan, callbackUrl);
    const authorizationUrl = response?.data?.authorization_url;
    if (authorizationUrl) {
      window.location.href = authorizationUrl;
    }
  } catch (error) {
    // Deliberately swallowed - see the function comment above.
  }
}
