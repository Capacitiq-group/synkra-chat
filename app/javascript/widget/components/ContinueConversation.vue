<script>
import { mapActions } from 'vuex';

// Synkra Chat identity layer: lets a visitor on a new device/browser who
// has chatted before request an email link to continue that conversation
// here. Collapsed by default (a small text link) to avoid cluttering the
// normal "start a new conversation" flow.
export default {
  data() {
    return {
      expanded: false,
      email: '',
      submitting: false,
      submitted: false,
    };
  },
  methods: {
    ...mapActions('contacts', ['requestContinuation']),
    expand() {
      this.expanded = true;
    },
    async submit() {
      if (!this.email || this.submitting) return;
      this.submitting = true;
      try {
        await this.requestContinuation(this.email);
        this.submitted = true;
      } finally {
        this.submitting = false;
      }
    },
  },
};
</script>

<template>
  <div class="text-center">
    <button
      v-if="!expanded"
      type="button"
      class="text-xs underline text-n-slate-11 hover:text-n-slate-12"
      @click="expand"
    >
      Chatted with us before? Continue on this device
    </button>

    <div v-else-if="!submitted" class="flex flex-col gap-2 mt-2">
      <input
        v-model="email"
        type="email"
        placeholder="Your email address"
        class="w-full px-3 py-2 text-sm border rounded-lg outline-none border-n-weak bg-n-alpha-1 text-n-slate-12"
        @keyup.enter="submit"
      />
      <button
        type="button"
        :disabled="submitting"
        class="w-full px-3 py-2 text-sm font-medium text-white rounded-lg bg-n-brand disabled:opacity-60"
        @click="submit"
      >
        {{ submitting ? 'Sending...' : 'Send me a link' }}
      </button>
    </div>

    <p v-else class="text-xs text-n-slate-11 mt-2">
      If that email matches a previous conversation, we've sent a link to
      continue it here.
    </p>
  </div>
</template>
