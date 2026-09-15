<script>
import { mapGetters } from 'vuex';

// Synkra Chat identity layer: a persistent (until dismissed), non-blocking
// nudge shown after the verification email is sent. Customers can keep
// chatting regardless - this never gates anything, it's purely informational.
export default {
  data() {
    return {
      dismissed: false,
    };
  },
  computed: {
    ...mapGetters('contacts', [
      'getCurrentUser',
      'isEmailVerified',
      'hasRequestedEmailVerification',
    ]),
    shouldShow() {
      return (
        !this.dismissed &&
        this.hasRequestedEmailVerification &&
        !this.isEmailVerified &&
        !!this.getCurrentUser.email
      );
    },
  },
  methods: {
    dismiss() {
      this.dismissed = true;
    },
  },
};
</script>

<template>
  <div
    v-if="shouldShow"
    class="flex items-center justify-between gap-2 px-4 py-2 text-sm bg-n-slate-3 text-n-slate-12 border-b border-n-weak"
  >
    <span>
      We sent a verification link to
      <strong>{{ getCurrentUser.email }}</strong> - click it so you never
      lose this conversation.
    </span>
    <button
      type="button"
      class="shrink-0 text-n-slate-11 hover:text-n-slate-12"
      aria-label="Dismiss"
      @click="dismiss"
    >
      &times;
    </button>
  </div>
</template>
