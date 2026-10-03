/* global axios */
import ApiClient from './ApiClient';

// Backs Synkra Chat's 'AI Agent > Actions' UI. Each Action the user
// configures in that friendly UI is, underneath, a
// Captain::CustomTool - a webhook the AI can call as a tool. This
// client talks to Chatwoot's own existing custom_tools API directly;
// no new backend routes were needed for this.
class CaptainCustomToolsAPI extends ApiClient {
  constructor() {
    super('captain/custom_tools', { accountScoped: true });
  }

  test(payload) {
    return axios.post(`${this.url}/test`, { custom_tool: payload });
  }
}

export default new CaptainCustomToolsAPI();
