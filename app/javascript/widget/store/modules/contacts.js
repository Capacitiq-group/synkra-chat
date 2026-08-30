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
};

const SET_CURRENT_USER = 'SET_CURRENT_USER';
const SET_EMAIL_VERIFICATION_REQUESTED = 'SET_EMAIL_VERIFICATION_REQUESTED';
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
};

export const mutations = {
  [SET_CURRENT_USER]($state, user) {
    const { currentUser } = $state;
    $state.currentUser = { ...currentUser, ...user };
  },
  [SET_EMAIL_VERIFICATION_REQUESTED]($state, value) {
    $state.emailVerificationRequested = value;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
