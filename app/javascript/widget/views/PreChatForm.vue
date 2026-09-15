<script>
import { mapActions } from 'vuex';
import { useRouter } from 'vue-router';
import PreChatForm from '../components/PreChat/Form.vue';
import configMixin from '../mixins/configMixin';
import { ON_CONVERSATION_CREATED } from '../constants/widgetBusEvents';
import { emitter } from 'shared/helpers/mitt';

export default {
  components: {
    PreChatForm,
  },
  mixins: [configMixin],
  setup() {
    const router = useRouter();
    return { router };
  },
  data() {
    return {
      // Synkra Chat identity layer: remembered so the background
      // global-identity request (fired once the conversation exists)
      // knows which email to link.
      lastSubmittedEmail: '',
    };
  },
  mounted() {
    // Register event listener for conversation creation
    emitter.on(ON_CONVERSATION_CREATED, this.handleConversationCreated);
  },
  beforeUnmount() {
    emitter.off(ON_CONVERSATION_CREATED, this.handleConversationCreated);
  },
  methods: {
    ...mapActions('conversation', ['clearConversations']),
    ...mapActions('conversationAttributes', ['clearConversationAttributes']),
    ...mapActions('contacts', [
      'requestEmailVerification',
      'requestGlobalIdentity',
    ]),
    handleConversationCreated() {
      // Synkra Chat identity layer: the global-identity OTP flow below
      // supersedes the older magic-link email verification (OTP success
      // already sets contact.email_verified_at too) - only one
      // verification prompt should ever reach the customer, so
      // requestEmailVerification is deliberately not called here
      // anymore. Left wired in the store/mailer/etc. rather than
      // deleted, in case we want it back for a case OTP doesn't cover.
      if (this.lastSubmittedEmail) {
        this.requestGlobalIdentity(this.lastSubmittedEmail);
      }
      // Redirect to messages page after conversation is created
      this.router.replace({ name: 'messages' });
      // Only after successful navigation, reset the isUpdatingRoute UIflag in app/javascript/widget/router.js
      // See issue: https://github.com/chatwoot/chatwoot/issues/10736
    },

    onSubmit({
      fullName,
      emailAddress,
      message,
      activeCampaignId,
      phoneNumber,
      contactCustomAttributes,
      conversationCustomAttributes,
    }) {
      // Contact custom attributes are sent within the same request that
      // identifies the contact. A separate update call would race the contact
      // merge on the server (matching email/phone) and write the values to
      // the destroyed contact, silently losing them.
      if (activeCampaignId) {
        emitter.emit('execute-campaign', {
          campaignId: activeCampaignId,
          customAttributes: conversationCustomAttributes,
        });
        this.$store.dispatch('contacts/update', {
          user: {
            email: emailAddress,
            name: fullName,
            phone_number: phoneNumber,
            custom_attributes: contactCustomAttributes,
          },
        });
      } else {
        this.lastSubmittedEmail = emailAddress;
        this.clearConversations();
        this.clearConversationAttributes();
        this.$store.dispatch('conversation/createConversation', {
          fullName: fullName,
          emailAddress: emailAddress,
          message: message,
          phoneNumber: phoneNumber,
          customAttributes: conversationCustomAttributes,
          contactCustomAttributes: contactCustomAttributes,
        });
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-1 overflow-auto">
    <PreChatForm :options="preChatFormOptions" @submit-pre-chat="onSubmit" />
  </div>
</template>
