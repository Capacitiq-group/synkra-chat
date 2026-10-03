import ApiClient from './ApiClient';

// Backs Synkra Chat's 'AI Agent > Business Brain' UI. One
// Captain::Assistant per account in our simplified model (Chatwoot's
// own API supports many per account, but the Business Brain concept
// Refilwe described is one configurable brain per business) - the
// frontend just uses whichever assistant comes first.
class CaptainAssistantsAPI extends ApiClient {
  constructor() {
    super('captain/assistants', { accountScoped: true });
  }
}

export default new CaptainAssistantsAPI();
