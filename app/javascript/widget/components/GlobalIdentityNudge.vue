<script>
import { mapActions, mapGetters } from 'vuex';

// Synkra Chat global identity layer: a persistent (until dismissed),
// non-blocking nudge inviting the customer to enter the OTP that was
// sent in the background after their first message. Purely optional -
// dismissing it or ignoring it never affects the conversation itself.
export default {
  data() {
    return {
      dismissed: false,
      otpCode: '',
      otpError: '',
      submitting: false,
    };
  },
  computed: {
    ...mapGetters('contacts', [
      'globalIdentityOtpRequired',
      'globalIdentityEmail',
      'globalIdentityLinked',
    ]),
    shouldShow() {
      return (
        !this.dismissed &&
        this.globalIdentityOtpRequired &&
        !this.globalIdentityLinked
      );
    },
  },
  methods: {
    ...mapActions('contacts', ['verifyGlobalIdentityOtp']),
    dismiss() {
      this.dismissed = true;
    },
    async submit() {
      if (!this.otpCode || this.submitting) return;
      this.submitting = true;
      this.otpError = '';
      try {
        const data = await this.verifyGlobalIdentityOtp({
          email: this.globalIdentityEmail,
          otp: this.otpCode,
        });
        if (!data.verified) {
          this.otpError = data.error || 'Incorrect code, please try again';
        }
      } catch (error) {
        this.otpError = 'Incorrect or expired code, please try again';
      } finally {
        this.submitting = false;
      }
    },
  },
};
</script>

<template>
  <div
    v-if="shouldShow"
    class="flex flex-col gap-2 px-4 py-2 text-sm bg-n-slate-3 text-n-slate-12 border-b border-n-weak"
  >
    <div class="flex items-center justify-between gap-2">
      <span
        >Enter the code we sent to
        <strong>{{ globalIdentityEmail }}</strong> to keep your history when
        you visit again.</span
      >
      <button
        type="button"
        class="shrink-0 text-n-slate-11 hover:text-n-slate-12"
        aria-label="Dismiss"
        @click="dismiss"
      >
        &times;
      </button>
    </div>
    <div class="flex gap-2">
      <input
        v-model="otpCode"
        type="text"
        inputmode="numeric"
        maxlength="6"
        placeholder="6-digit code"
        class="flex-1 px-3 py-1.5 text-sm border rounded-lg outline-none border-n-weak bg-n-alpha-1 text-n-slate-12"
        @keyup.enter="submit"
      />
      <button
        type="button"
        :disabled="submitting"
        class="px-3 py-1.5 text-sm font-medium text-white rounded-lg bg-n-brand disabled:opacity-60"
        @click="submit"
      >
        {{ submitting ? '...' : 'Verify' }}
      </button>
    </div>
    <p v-if="otpError" class="text-n-ruby-9">{{ otpError }}</p>
  </div>
</template>
