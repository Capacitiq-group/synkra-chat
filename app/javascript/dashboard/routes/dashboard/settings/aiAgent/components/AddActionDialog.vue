<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import { useAlert } from 'dashboard/composables';
import CaptainCustomToolsAPI from 'dashboard/api/captainCustomTools';
import { ACTION_PRESETS } from '../actionPresets';

const emit = defineEmits(['created']);

const { t } = useI18n();

const dialogRef = ref(null);
const step = ref('pick');
const selectedPreset = ref(null);
const actionName = ref('');
const webhookUrl = ref('');
const authType = ref('none');
const authValue = ref('');
const isSaving = ref(false);
const isTesting = ref(false);
const testResult = ref(null);

const AUTH_OPTIONS = [
  { value: 'none', label: 'No authentication' },
  { value: 'bearer', label: 'Bearer token' },
  { value: 'api_key', label: 'API key' },
];

const canSave = computed(
  () => actionName.value.trim() && webhookUrl.value.trim()
);

const resetState = () => {
  step.value = 'pick';
  selectedPreset.value = null;
  actionName.value = '';
  webhookUrl.value = '';
  authType.value = 'none';
  authValue.value = '';
  testResult.value = null;
};

const open = () => {
  resetState();
  dialogRef.value?.open();
};

const selectPreset = preset => {
  selectedPreset.value = preset;
  actionName.value = t(preset.titleKey);
  step.value = 'form';
};

const backToPicker = () => {
  step.value = 'pick';
};

const buildAuthConfig = () => {
  if (authType.value === 'none') return {};
  if (authType.value === 'bearer') return { token: authValue.value };
  // api_key: Captain's HttpTool convention - header name fixed to a
  // sensible default here since exposing a custom header-name field
  // would reintroduce the raw-config complexity we're hiding.
  return { header_name: 'X-API-Key', value: authValue.value };
};

const buildPayload = () => ({
  title: actionName.value.trim(),
  description: selectedPreset.value.toolDescription,
  endpoint_url: webhookUrl.value.trim(),
  http_method: 'POST',
  auth_type: authType.value,
  auth_config: buildAuthConfig(),
  param_schema: selectedPreset.value.paramSchema,
  enabled: true,
});

const handleTest = async () => {
  if (!webhookUrl.value.trim()) return;
  isTesting.value = true;
  testResult.value = null;
  try {
    const response = await CaptainCustomToolsAPI.test(buildPayload());
    testResult.value = { ok: true, message: response.data.body };
  } catch (error) {
    testResult.value = {
      ok: false,
      message: error.response?.data?.error || 'Test failed',
    };
  } finally {
    isTesting.value = false;
  }
};

const handleConfirm = async () => {
  if (!canSave.value) return;
  isSaving.value = true;
  try {
    await CaptainCustomToolsAPI.create({ custom_tool: buildPayload() });
    useAlert(t('AI_AGENT_SETTINGS.ACTIONS.CREATED'));
    dialogRef.value?.close();
    emit('created');
  } catch (error) {
    useAlert(
      error.response?.data?.error || t('AI_AGENT_SETTINGS.ACTIONS.CREATE_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="lg"
    :title="
      step === 'pick'
        ? t('AI_AGENT_SETTINGS.ACTIONS.ADD_TITLE')
        : t(selectedPreset.titleKey)
    "
    :show-confirm-button="step === 'form'"
    :show-cancel-button="step === 'form'"
    :confirm-button-label="t('AI_AGENT_SETTINGS.ACTIONS.SAVE_BUTTON')"
    :disable-confirm-button="!canSave"
    :is-loading="isSaving"
    @confirm="handleConfirm"
  >
    <div v-if="step === 'pick'" class="grid sm:grid-cols-2 gap-3">
      <button
        v-for="preset in ACTION_PRESETS"
        :key="preset.key"
        type="button"
        class="flex items-start gap-3 p-4 rounded-xl border border-n-weak bg-n-solid-2 text-start hover:border-n-brand transition-colors"
        @click="selectPreset(preset)"
      >
        <Icon :icon="preset.icon" class="size-5 flex-shrink-0 mt-0.5" />
        <div>
          <p class="text-sm font-medium text-n-slate-12">
            {{ t(preset.titleKey) }}
          </p>
          <p class="text-xs text-n-slate-11 mt-0.5">
            {{ t(preset.descriptionKey) }}
          </p>
        </div>
      </button>
    </div>

    <div v-else class="flex flex-col gap-4">
      <Input
        v-model="actionName"
        :label="t('AI_AGENT_SETTINGS.ACTIONS.NAME_LABEL')"
        :placeholder="t('AI_AGENT_SETTINGS.ACTIONS.NAME_PLACEHOLDER')"
      />
      <Input
        v-model="webhookUrl"
        :label="t('AI_AGENT_SETTINGS.ACTIONS.URL_LABEL')"
        :message="t('AI_AGENT_SETTINGS.ACTIONS.URL_HELP')"
        placeholder="https://flow.synkra.co.za/webhooks/..."
      />
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('AI_AGENT_SETTINGS.ACTIONS.AUTH_LABEL') }}
        </label>
        <Select v-model="authType" :options="AUTH_OPTIONS" />
      </div>
      <Input
        v-if="authType !== 'none'"
        v-model="authValue"
        type="password"
        :label="
          authType === 'bearer'
            ? t('AI_AGENT_SETTINGS.ACTIONS.TOKEN_LABEL')
            : t('AI_AGENT_SETTINGS.ACTIONS.API_KEY_LABEL')
        "
      />

      <div class="flex items-center gap-3">
        <button
          type="button"
          class="text-sm text-n-brand hover:underline disabled:opacity-50"
          :disabled="!webhookUrl.trim() || isTesting"
          @click="handleTest"
        >
          {{
            isTesting
              ? t('AI_AGENT_SETTINGS.ACTIONS.TESTING')
              : t('AI_AGENT_SETTINGS.ACTIONS.TEST_BUTTON')
          }}
        </button>
        <button type="button" class="text-sm text-n-slate-11 hover:underline" @click="backToPicker">
          {{ t('AI_AGENT_SETTINGS.ACTIONS.CHANGE_TYPE') }}
        </button>
      </div>
      <p
        v-if="testResult"
        class="text-xs"
        :class="testResult.ok ? 'text-n-teal-11' : 'text-n-ruby-11'"
      >
        {{ testResult.message }}
      </p>
    </div>
  </Dialog>
</template>
