/* global axios */
import ApiClient from './ApiClient';

// "Automations" - the Chat-facing name for the Chat<->Flow bridge (see
// docs/synkra/automations-flow-bridge.md). Read-only: there is no key
// or "connect" flow exposed here on purpose - provisioning happens
// automatically server-side and the business never sees a Flow API key.
class AutomationsAPI extends ApiClient {
  constructor() {
    super('automations/credits', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }
}

export default new AutomationsAPI();
