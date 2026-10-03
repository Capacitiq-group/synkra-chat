import { sendMessage } from 'widget/helpers/utils';
import ContactsAPI from '../../api/contacts';
import { SET_USER_ERROR } from '../../constants/errorTypes';
import { setHeader } from '../../helpers/axios';
const state = {
  currentUser: {},
  // Synkra Chat identity layer: tracks whether we've already asked the
  // backend to send a verification email this session, so we don't
  // fire it repeatedly (e.g. on every contact refetch).
  emailVerificationRequested: false,
  // Synkra Chat global identity layer: whether the last background
  // global-identity request came back needing an OTP, and which email
  // it's for - drives the (dismissible, non-blocking) OTP nudge shown
  // in Messages.vue.
  globalIdentityOtpRequired: false,
  globalIdentityEmail: '',
  globalIdentityLinked: false,
};

const SET_CURRENT_USER = 'SET_CURRENT_USER';
const SET_EMAIL_VERIFICATION_REQUESTED = 'SET_EMAIL_VERIFICATION_REQUESTED';
const SET_GLOBAL_IDENTITY_STATE = 'SET_GLOBAL_IDENTITY_STATE';
const parseErrorData = error =>
  error && error.response && error.response.data ? error.response.data : error;
export const updateWidgetAuthToken = widgetAuthToken => {
  if (widgetAuthToken) {
    setHeader(widgetAuthToken);
    sendMessage({
      event: 'setAuthCookie',
      data: { widgetAuthToken },
    });
  }
};

export const getters = {
  getCurrentUser(_state) {
    return _state.currentUser;
  },
  // Synkra Chat identity layer
  isEmailVerified(_state) {
    return !!_state.currentUser.email_verified;
  },
  hasRequestedEmailVerification(_state) {
    return _state.emailVerificationRequested;
  },
  globalIdentityOtpRequired(_state) {
    return _state.globalIdentityOtpRequired;
  },
  globalIdentityEmail(_state) {
    return _state.globalIdentityEmail;
  },
  globalIdentityLinked(_state) {
    return _state.globalIdentityLinked;
  },
};

export const actions = {
  get: async ({ commit }) => {
    try {
      const { data } = await ContactsAPI.get();
      commit(SET_CURRENT_USER, data);
    } catch (error) {
      // Ignore error
    }
  },
  update: async ({ dispatch }, { user }) => {
    try {
      await ContactsAPI.update(user);
      dispatch('get');
    } catch (error) {
      // Ignore error
    }
  },
  setUser: async ({ dispatch }, { identifier, user: userObject }) => {
    try {
      const {
        email,
        name,
        avatar_url,
        identifier_hash: identifierHash,
        phone_number,
        company_name,
        city,
        country_code,
        description,
        custom_attributes,
        social_profiles,
      } = userObject;
      const user = {
        email,
        name,
        avatar_url,
        identifier_hash: identifierHash,
        phone_number,
        additional_attributes: {
          company_name,
          city,
          description,
          country_code,
          social_profiles,
        },
        custom_attributes,
      };
      const {
        data: { widget_auth_token: widgetAuthToken },
      } = await ContactsAPI.setUser(identifier, user);
      updateWidgetAuthToken(widgetAuthToken);
      dispatch('get');
      if (identifierHash || widgetAuthToken) {
        dispatch('conversation/clearConversations', {}, { root: true });
        dispatch('conversation/fetchOldConversations', {}, { root: true });
        dispatch('conversationAttributes/getAttributes', {}, { root: true });
      }
    } catch (error) {
      const data = parseErrorData(error);
      sendMessage({ event: 'error', errorType: SET_USER_ERROR, data });
    }
  },
  setCustomAttributes: async (_, customAttributes = {}) => {
    try {
      await ContactsAPI.setCustomAttributes(customAttributes);
    } catch (error) {
      // Ignore error
    }
  },
  deleteCustomAttribute: async (_, customAttribute) => {
    try {
      await ContactsAPI.deleteCustomAttribute(customAttribute);
    } catch (error) {
      // Ignore error
    }
  },
  // Synkra Chat identity layer: fire-and-forget, non-blocking. If it
  // fails (network hiccup, etc.) the customer can still chat normally -
  // this only affects the "check your email" nudge, never the actual
  // conversation.
  requestEmailVerification: async ({ commit, state: _state }) => {
    if (_state.emailVerificationRequested) return;
    commit(SET_EMAIL_VERIFICATION_REQUESTED, true);
    try {
      await ContactsAPI.verifyEmail();
    } catch (error) {
      // Ignore error - non-critical, customer can still chat
    }
  },
  // Synkra Chat identity layer: cross-device continuation. Always
  // resolves successfully from the caller's perspective (backend never
  // reveals whether the email matched anything, to avoid leaking which
  // emails have chatted before).
  requestContinuation: async (_, email) => {
    await ContactsAPI.requestContinuation(email);
  },
  // Synkra Chat global identity layer: fire-and-forget from the caller's
  // perspective (never throws), but commits state so the OTP nudge
  // component can react. Runs only after a conversation/contact already
  // exists - never blocks or gates the first message.
  requestGlobalIdentity: async ({ commit }, email) => {
    try {
      const { data } = await ContactsAPI.requestGlobalIdentity(email);
      commit(SET_GLOBAL_IDENTITY_STATE, {
        globalIdentityOtpRequired: !!data.otp_required,
        globalIdentityEmail: email,
        globalIdentityLinked: !!data.linked,
      });
    } catch (error) {
      // Ignore error - non-critical, customer can still chat
    }
  },
  verifyGlobalIdentityOtp: async ({ commit }, { email, otp }) => {
    const { data } = await ContactsAPI.verifyGlobalIdentityOtp(email, otp);
    if (data.verified) {
      commit(SET_GLOBAL_IDENTITY_STATE, {
        globalIdentityOtpRequired: false,
        globalIdentityEmail: email,
        globalIdentityLinked: true,
      });
    }
    return data;
  },
};

export const mutations = {
  [SET_CURRENT_USER]($state, user) {
    const { currentUser } = $state;
    $state.currentUser = { ...currentUser, ...user };
  },
  [SET_EMAIL_VERIFICATION_REQUESTED]($state, value) {
    $state.emailVerificationRequested = value;
  },
  [SET_GLOBAL_IDENTITY_STATE]($state, payload) {
    Object.assign($state, payload);
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
