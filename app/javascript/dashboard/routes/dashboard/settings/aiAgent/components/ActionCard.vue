<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ButtonV4 from 'next/button/Button.vue';

defineProps({
  tool: { type: Object, required: true },
});

const emit = defineEmits(['delete']);

const { t } = useI18n();
</script>

<template>
  <div
    class="flex items-center justify-between gap-4 p-4 rounded-xl border border-n-weak bg-n-solid-2"
  >
    <div class="flex items-start gap-3 min-w-0">
      <Icon icon="i-lucide-zap" class="size-5 flex-shrink-0 mt-0.5" />
      <div class="min-w-0">
        <p class="text-sm font-medium text-n-slate-12 truncate">
          {{ tool.title }}
        </p>
        <p class="text-xs text-n-slate-11 truncate">{{ tool.endpoint_url }}</p>
      </div>
    </div>
    <ButtonV4
      sm
      faded
      ruby
      icon="i-lucide-trash-2"
      :label="t('AI_AGENT_SETTINGS.ACTIONS.DELETE_BUTTON')"
      @click="emit('delete', tool.id)"
    />
  </div>
</template>
