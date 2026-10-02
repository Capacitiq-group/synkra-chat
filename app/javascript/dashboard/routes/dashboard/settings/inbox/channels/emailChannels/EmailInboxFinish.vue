<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
  inboxId: {
    type: [String, Number],
    required: true,
  },
});

const { t } = useI18n();

const activeTab = ref('gmail');

const message = computed(() => {
  return props.inbox.forwarding_enabled
    ? t('INBOX_MGMT.ADD.EMAIL_CHANNEL.FINISH_MESSAGE')
    : t('INBOX_MGMT.ADD.EMAIL_CHANNEL.FINISH_MESSAGE_NO_FORWARDING');
});

const showForwardingAddress = computed(() => {
  return props.inbox.forwarding_enabled;
});

const tabs = computed(() => [
  {
    key: 'gmail',
    label: t('INBOX_MGMT.ADD.EMAIL_CHANNEL.FINISH_INSTRUCTIONS.GMAIL_TAB'),
    steps: t('INBOX_MGMT.ADD.EMAIL_CHANNEL.FINISH_INSTRUCTIONS.GMAIL_STEPS'),
  },
  {
    key: 'microsoft',
    label: t('INBOX_MGMT.ADD.EMAIL_CHANNEL.FINISH_INSTRUCTIONS.MICROSOFT_TAB'),
    steps: t('INBOX_MGMT.ADD.EMAIL_CHANNEL.FINISH_INSTRUCTIONS.MICROSOFT_STEPS'),
  },
  {
    key: 'other',
    label: t('INBOX_MGMT.ADD.EMAIL_CHANNEL.FINISH_INSTRUCTIONS.OTHER_TAB'),
    steps: t('INBOX_MGMT.ADD.EMAIL_CHANNEL.FINISH_INSTRUCTIONS.OTHER_STEPS'),
  },
]);

const activeSteps = computed(() => {
  const found = tabs.value.find(tab => tab.key === activeTab.value);
  return found ? found.steps : '';
});
</script>

<template>
  <div class="w-full max-w-3xl mx-auto text-left">
    <p class="text-base text-n-slate-11 mt-4 leading-7">
      {{ message }}
    </p>

    <div v-if="showForwardingAddress" class="mt-8">
      <p class="mb-3 font-medium text-n-slate-12">
        {{ $t('INBOX_MGMT.ADD.EMAIL_CHANNEL.FORWARDING_ADDRESS_LABEL') }}
      </p>
      <woot-code lang="html" :script="inbox.forward_to_email" />
    </div>

    <div
      v-if="showForwardingAddress"
      class="mt-10 border border-n-weak rounded-xl p-6 bg-n-alpha-1"
    >
      <h3 class="text-base font-medium text-n-slate-12">
        {{
          $t(
            'INBOX_MGMT.ADD.EMAIL_CHANNEL.FINISH_INSTRUCTIONS.HEADING'
          )
        }}
      </h3>
      <p class="mt-2 text-sm text-n-slate-11 leading-6">
        {{
          $t(
            'INBOX_MGMT.ADD.EMAIL_CHANNEL.FINISH_INSTRUCTIONS.DESCRIPTION'
          )
        }}
      </p>

      <div class="mt-5 flex gap-2 border-b border-n-weak pb-3">
        <button
          v-for="tab in tabs"
          :key="tab.key"
          type="button"
          class="px-3 py-1.5 rounded-md text-sm transition-colors"
          :class="
            activeTab === tab.key
              ? 'bg-n-brand text-white font-medium'
              : 'text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="activeTab = tab.key"
        >
          {{ tab.label }}
        </button>
      </div>

      <pre
        class="mt-5 whitespace-pre-wrap text-sm text-n-slate-12 leading-6 font-sans"
        >{{ activeSteps }}</pre
      >
    </div>
  </div>
</template>
