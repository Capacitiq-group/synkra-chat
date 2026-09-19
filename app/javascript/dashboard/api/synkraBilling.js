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
}

export default new SynkraBillingAPI();
