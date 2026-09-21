/* global axios */
import ApiClient from './ApiClient';

// Synkra Student Programme - email one-time-code verification. A
// singleton resource per account, like billing/subscription.
class SynkraStudentVerificationAPI extends ApiClient {
  constructor() {
    super('billing/student_verification', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  sendCode({ localPart, institution, extension }) {
    return axios.post(this.url, {
      local_part: localPart,
      institution,
      extension,
    });
  }

  confirm(code) {
    return axios.post(`${this.url}/confirm`, { code });
  }
}

export default new SynkraStudentVerificationAPI();
