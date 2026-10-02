/* global axios */
import ApiClient from './ApiClient';

// Synkra Chat's own billing (Paystack-backed) - a singleton resource
// per account, not a CRUD collection, so this intentionally doesn't
// use ApiClient's default index/show/create/update/delete helpers.
class SynkraBillingAPI extends ApiClient {
  constructor() {
    super('billing/subscription', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  checkout(plan, callbackUrl) {
    return axios.post(`${this.url}/checkout`, {
      plan,
      callback_url: callbackUrl,
    });
  }

  changePlan(plan) {
    return axios.post(`${this.url}/change_plan`, { plan });
  }

  cancel() {
    return axios.post(`${this.url}/cancel`);
  }

  resume() {
    return axios.post(`${this.url}/resume`);
  }

  // Display-only - toggles which currency Chat's own billing UI shows
  // prices in. Never changes what's actually charged via Paystack
  // (always ZAR) - see SynkraSubscription#preferred_currency.
  setCurrency(currency) {
    return axios.post(`${this.url}/set_currency`, { currency });
  }

  buyMessageAddon(packKey) {
    return axios.post(
      `/api/v1/accounts/${this.accountIdFromRoute}/billing/message_addons`,
      { pack_key: packKey }
    );
  }

  buyExtraSeats(quantity) {
    return axios.post(
      `/api/v1/accounts/${this.accountIdFromRoute}/billing/extra_seats`,
      { quantity }
    );
  }

  buyExtraStorage(gb) {
    return axios.post(
      `/api/v1/accounts/${this.accountIdFromRoute}/billing/extra_storage`,
      { gb }
    );
  }
  buyAiOpsAddon(packKey) {
    return axios.post(
      `/api/v1/accounts/${this.accountIdFromRoute}/billing/ai_ops_addons`,
      { pack_key: packKey }
    );
  }
  buyNotificationEmailAddon(packKey) {
    return axios.post(
      `/api/v1/accounts/${this.accountIdFromRoute}/billing/notification_email_addons`,
      { pack_key: packKey }
    );
  }
}

export default new SynkraBillingAPI();
