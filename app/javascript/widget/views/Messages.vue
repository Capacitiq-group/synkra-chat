<script>
import { mapGetters } from 'vuex';

import ChatFooter from '../components/ChatFooter.vue';
import ConversationWrap from '../components/ConversationWrap.vue';
import GlobalIdentityNudge from '../components/GlobalIdentityNudge.vue';

export default {
  components: {
    ChatFooter,
    ConversationWrap,
    GlobalIdentityNudge,
  },
  computed: {
    ...mapGetters({
      groupedMessages: 'conversation/getGroupedConversation',
    }),
  },
  mounted() {
    this.$store.dispatch('conversation/setUserLastSeen');
  },
};
</script>

<template>
  <div
    class="flex flex-col flex-1 overflow-hidden rounded-b-lg bg-n-slate-2 dark:bg-n-solid-1"
  >
    <!-- Synkra Chat: EmailVerificationNudge (magic-link based) is
         superseded by GlobalIdentityNudge (OTP based) - kept in the
         codebase, just not rendered, to avoid double-prompting for
         the same thing. -->
    <GlobalIdentityNudge />
    <div class="flex flex-1 overflow-auto">
      <ConversationWrap :grouped-messages="groupedMessages" />
    </div>
    <ChatFooter class="px-5" />
  </div>
</template>
