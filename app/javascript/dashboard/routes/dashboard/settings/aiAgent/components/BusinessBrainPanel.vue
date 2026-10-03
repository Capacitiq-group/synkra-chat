<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CaptainAssistantsAPI from 'dashboard/api/captainAssistants';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import ButtonV4 from 'next/button/Button.vue';
import DynamicListField from './DynamicListField.vue';

const { t } = useI18n();

const isFetching = ref(true);
const isSaving = ref(false);
const fetchError = ref(false);
const assistantId = ref(null);

const name = ref('');
const description = ref('');
const productName = ref('');
const instructions = ref('');
const welcomeMessage = ref('');
const handoffMessage = ref('');
const guardrails = ref([]);
const responseGuidelines = ref([]);

const populateFromAssistant = assistant => {
  assistantId.value = assistant.id;
  name.value = assistant.name || '';
  description.value = assistant.description || '';
  productName.value = assistant.config?.product_name || '';
  instructions.value = assistant.config?.instructions || '';
  welcomeMessage.value = assistant.config?.welcome_message || '';
  handoffMessage.value = assistant.config?.handoff_message || '';
  guardrails.value = assistant.guardrails?.length ? [...assistant.guardrails] : [];
  responseGuidelines.value = assistant.response_guidelines?.length
    ? [...assistant.response_guidelines]
    : [];
};

const fetchAssistant = async () => {
  isFetching.value = true;
  fetchError.value = false;
  try {
    const response = await CaptainAssistantsAPI.get();
    const [existing] = response.data.payload;
    if (existing) populateFromAssistant(existing);
  } catch (error) {
    fetchError.value = true;
  } finally {
    isFetching.value = false;
  }
};

const buildPayload = () => ({
  assistant: {
    name: name.value.trim(),
    description: description.value.trim(),
    // Only non-empty lines - an empty text box left by "+ Add" but
    // never filled in shouldn't become a blank rule the LLM sees.
    guardrails: guardrails.value.map(g => g.trim()).filter(Boolean),
    response_guidelines: responseGuidelines.value
      .map(g => g.trim())
      .filter(Boolean),
    config: {
      product_name: productName.value.trim(),
      instructions: instructions.value.trim(),
      welcome_message: welcomeMessage.value.trim(),
      handoff_message: handoffMessage.value.trim(),
    },
  },
});

const handleSave = async () => {
  if (!name.value.trim() || !description.value.trim()) {
    useAlert(t('AI_AGENT_SETTINGS.BRAIN.VALIDATION_ERROR'));
    return;
  }
  isSaving.value = true;
  try {
    const response = assistantId.value
      ? await CaptainAssistantsAPI.update(assistantId.value, buildPayload())
      : await CaptainAssistantsAPI.create(buildPayload());
    populateFromAssistant(response.data);
    useAlert(t('AI_AGENT_SETTINGS.BRAIN.SAVED'));
  } catch (error) {
    useAlert(
      error.response?.data?.message || t('AI_AGENT_SETTINGS.BRAIN.SAVE_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

onMounted(fetchAssistant);
</script>

<template>
  <div v-if="isFetching" class="text-sm text-n-slate-11">
    {{ t('AI_AGENT_SETTINGS.LOADING') }}
  </div>
  <p v-else-if="fetchError" class="text-sm text-n-ruby-11">
    {{ t('AI_AGENT_SETTINGS.ERRORS.FETCH') }}
  </p>
  <div v-else class="flex flex-col gap-6 max-w-2xl">
    <div class="grid sm:grid-cols-2 gap-4">
      <Input
        v-model="name"
        :label="t('AI_AGENT_SETTINGS.BRAIN.NAME_LABEL')"
        :placeholder="t('AI_AGENT_SETTINGS.BRAIN.NAME_PLACEHOLDER')"
      />
      <Input
        v-model="productName"
        :label="t('AI_AGENT_SETTINGS.BRAIN.PRODUCT_LABEL')"
        :placeholder="t('AI_AGENT_SETTINGS.BRAIN.PRODUCT_PLACEHOLDER')"
      />
    </div>

    <TextArea
      v-model="description"
      :label="t('AI_AGENT_SETTINGS.BRAIN.DESCRIPTION_LABEL')"
      :placeholder="t('AI_AGENT_SETTINGS.BRAIN.DESCRIPTION_PLACEHOLDER')"
      :max-length="500"
      show-character-count
    />

    <TextArea
      v-model="instructions"
      :label="t('AI_AGENT_SETTINGS.BRAIN.INSTRUCTIONS_LABEL')"
      :placeholder="t('AI_AGENT_SETTINGS.BRAIN.INSTRUCTIONS_PLACEHOLDER')"
      :max-length="4000"
      show-character-count
      auto-height
      min-height="8rem"
      max-height="20rem"
    />

    <div class="grid sm:grid-cols-2 gap-4">
      <Input
        v-model="welcomeMessage"
        :label="t('AI_AGENT_SETTINGS.BRAIN.WELCOME_LABEL')"
        :placeholder="t('AI_AGENT_SETTINGS.BRAIN.WELCOME_PLACEHOLDER')"
      />
      <Input
        v-model="handoffMessage"
        :label="t('AI_AGENT_SETTINGS.BRAIN.HANDOFF_LABEL')"
        :placeholder="t('AI_AGENT_SETTINGS.BRAIN.HANDOFF_PLACEHOLDER')"
      />
    </div>

    <div class="flex flex-col gap-1">
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('AI_AGENT_SETTINGS.BRAIN.GUARDRAILS_LABEL') }}
      </label>
      <p class="text-xs text-n-slate-11 mb-1">
        {{ t('AI_AGENT_SETTINGS.BRAIN.GUARDRAILS_HELP') }}
      </p>
      <DynamicListField
        v-model="guardrails"
        :placeholder="t('AI_AGENT_SETTINGS.BRAIN.GUARDRAILS_PLACEHOLDER')"
        :add-label="t('AI_AGENT_SETTINGS.BRAIN.ADD_RULE')"
      />
    </div>

    <div class="flex flex-col gap-1">
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('AI_AGENT_SETTINGS.BRAIN.RESPONSE_GUIDELINES_LABEL') }}
      </label>
      <p class="text-xs text-n-slate-11 mb-1">
        {{ t('AI_AGENT_SETTINGS.BRAIN.RESPONSE_GUIDELINES_HELP') }}
      </p>
      <DynamicListField
        v-model="responseGuidelines"
        :placeholder="t('AI_AGENT_SETTINGS.BRAIN.RESPONSE_GUIDELINE_PLACEHOLDER')"
        :add-label="t('AI_AGENT_SETTINGS.BRAIN.ADD_GUIDELINE')"
      />
    </div>

    <ButtonV4
      solid
      blue
      class="self-start"
      :is-loading="isSaving"
      :label="t('AI_AGENT_SETTINGS.BRAIN.SAVE_BUTTON')"
      @click="handleSave"
    />
  </div>
</template>
