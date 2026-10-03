/* global axios */
import ApiClient from './ApiClient';

// Backs Synkra Chat's 'AI Agent > Knowledge Base' UI - a thin client
// over Chatwoot's own existing Captain documents API. Website links
// get periodically re-crawled (captain_document_auto_sync, already
// enabled account-wide); PDFs are a one-time upload with no ongoing
// sync.
class CaptainDocumentsAPI extends ApiClient {
  constructor() {
    super('captain/documents', { accountScoped: true });
  }

  sync(id) {
    return axios.post(`${this.url}/${id}/sync`);
  }
}

export default new CaptainDocumentsAPI();
