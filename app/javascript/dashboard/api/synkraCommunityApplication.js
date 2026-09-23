/* global axios */
import ApiClient from './ApiClient';

// Synkra Community Access Programme - application, status, and adding
// information when a reviewer asks for it.
class SynkraCommunityApplicationAPI extends ApiClient {
  constructor() {
    super('billing/community_application', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  // fields: plain object of form answers; files: File[]
  submit(fields, files) {
    const formData = new FormData();
    Object.entries(fields).forEach(([key, value]) => {
      if (value !== '' && value !== null && value !== undefined) {
        formData.append(key, value);
      }
    });
    files.forEach(file => formData.append('documents[]', file));
    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  addInformation(message, files) {
    const formData = new FormData();
    formData.append('message', message || '');
    files.forEach(file => formData.append('documents[]', file));
    return axios.patch(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  // Attaches an approved public application (submitted at
  // /community-access with no login) to this now-existing account.
  claim(accessToken) {
    return axios.post(`${this.url}/claim`, { access_token: accessToken });
  }
}

export default new SynkraCommunityApplicationAPI();
