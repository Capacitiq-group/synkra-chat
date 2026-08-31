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
      // Synkra Chat global identity layer: holds the pre-chat form
      // submission while we establish identity, and OTP-step UI state.
      showOtpStep: false,
      otpEmail: '',
      otpCode: '',
      otpError: '',
      submittingOtp: false,
      pendingFormData: null,
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
      'verifyGlobalIdentityOtp',
    ]),
    handleConversationCreated() {
      // Synkra Chat identity layer: kick off email verification in the
      // background - never blocks navigation to the chat.
      this.requestEmailVerification();
      // Redirect to messages page after conversation is created
      this.router.replace({ name: 'messages' });
      // Only after successful navigation, reset the isUpdatingRoute UIflag in app/javascript/widget/router.js
      // See issue: https://github.com/chatwoot/chatwoot/issues/10736
    },

    createConversationFromPending() {
      const formData = this.pendingFormData;
      this.clearConversations();
      this.clearConversationAttributes();
      this.$store.dispatch('conversation/createConversation', {
        fullName: formData.fullName,
        emailAddress: formData.emailAddress,
        message: formData.message,
        phoneNumber: formData.phoneNumber,
        customAttributes: formData.conversationCustomAttributes,
        contactCustomAttributes: formData.contactCustomAttributes,
      });
    },

    async submitOtp() {
      if (!this.otpCode || this.submittingOtp) return;
      this.submittingOtp = true;
      this.otpError = '';
      try {
        const data = await this.verifyGlobalIdentityOtp({
          email: this.otpEmail,
          otp: this.otpCode,
        });
        if (data.verified) {
          this.createConversationFromPending();
        } else {
          this.otpError = data.error || 'Incorrect code, please try again';
        }
      } catch (error) {
        this.otpError = 'Incorrect or expired code, please try again';
      } finally {
        this.submittingOtp = false;
      }
    },

    async onSubmit(formData) {
      const { emailAddress, activeCampaignId, conversationCustomAttributes } =
        formData;
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
            name: formData.fullName,
            phone_number: formData.phoneNumber,
            custom_attributes: formData.contactCustomAttributes,
          },
        });
        return;
      }

      // Synkra Chat global identity layer: if no email was collected on
      // this inbox (email disabled in the pre-chat form config), fall
      // straight back to the original behaviour rather than forcing OTP.
      if (!emailAddress) {
        this.pendingFormData = formData;
        this.createConversationFromPending();
        return;
      }

      this.pendingFormData = formData;
      this.otpEmail = emailAddress;
      const data = await this.requestGlobalIdentity(emailAddress);
      if (data.otp_required) {
        this.showOtpStep = true;
      } else {
        this.createConversationFromPending();
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-1 overflow-auto">
    <div v-if="showOtpStep" class="flex flex-col w-full gap-3 p-4">
      <h3 class="text-base font-medium text-n-slate-12">
        Enter your verification code
      </h3>
      <p class="text-sm text-n-slate-11">
        We sent a code to <strong>{{ otpEmail }}</strong
        >.
      </p>
      <input
        v-model="otpCode"
        type="text"
        inputmode="numeric"
        maxlength="6"
        placeholder="6-digit code"
        class="w-full px-3 py-2 text-lg tracking-widest text-center border rounded-lg outline-none border-n-weak bg-n-alpha-1 text-n-slate-12"
        @keyup.enter="submitOtp"
      />
      <p v-if="otpError" class="text-sm text-n-ruby-9">{{ otpError }}</p>
      <button
        type="button"
        :disabled="submittingOtp"
        class="w-full px-3 py-2 text-sm font-medium text-white rounded-lg bg-n-brand disabled:opacity-60"
        @click="submitOtp"
      >
        {{ submittingOtp ? 'Verifying...' : 'Verify and start chatting' }}
      </button>
    </div>
    <PreChatForm
      v-else
      :options="preChatFormOptions"
      @submit-pre-chat="onSubmit"
    />
  </div>
</template>
