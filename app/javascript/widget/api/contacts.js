import { API } from 'widget/helpers/axios';

const buildUrl = endPoint => `/api/v1/${endPoint}${window.location.search}`;

export default {
  get() {
    return API.get(buildUrl('widget/contact'));
  },
  update(userObject) {
    return API.patch(buildUrl('widget/contact'), userObject);
  },
  setUser(identifier, userObject) {
    return API.patch(buildUrl('widget/contact/set_user'), {
      identifier,
      ...userObject,
    });
  },
  setCustomAttributes(customAttributes = {}) {
    return API.patch(buildUrl('widget/contact'), {
      custom_attributes: customAttributes,
    });
  },
  deleteCustomAttribute(customAttribute) {
    return API.post(buildUrl('widget/contact/destroy_custom_attributes'), {
      custom_attributes: [customAttribute],
    });
  },
  // Synkra Chat identity layer: triggers sending the email verification
  // link. Safe to call even if already verified (backend just returns
  // { verified: true } without sending anything).
  verifyEmail() {
    return API.post(buildUrl('widget/contact_verification'));
  },
  // Synkra Chat identity layer: for a visitor on a new device who has
  // chatted before. Does not require any existing auth - that's the
  // point.
  requestContinuation(email) {
    return API.post(buildUrl('widget/contact_continuation'), { email });
  },
  // Synkra Chat global identity layer
  requestGlobalIdentity(email) {
    return API.post(buildUrl('widget/global_identity'), { email });
  },
  verifyGlobalIdentityOtp(email, otp) {
    return API.post(buildUrl('widget/global_identity/verify_otp'), {
      email,
      otp,
    });
  },
};
