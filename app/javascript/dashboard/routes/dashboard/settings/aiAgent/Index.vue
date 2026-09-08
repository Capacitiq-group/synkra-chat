<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CaptainCustomToolsAPI from 'dashboard/api/captainCustomTools';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import ActionCard from './components/ActionCard.vue';
import AddActionDialog from './components/AddActionDialog.vue';
import BusinessBrainPanel from './components/BusinessBrainPanel.vue';
import KnowledgeBasePanel from './components/KnowledgeBasePanel.vue';
import ButtonV4 from 'next/button/Button.vue';

const { t } = useI18n();

const activeTab = ref('brain');

const tools = ref([]);
const isFetching = ref(false);
const fetchError = ref(false);
const addDialogRef = ref(null);

const fetchTools = async () => {
  isFetching.value = true;
  fetchError.value = false;
  try {
    const response = await CaptainCustomToolsAPI.get();
    tools.value = response.data.payload;
  } catch (error) {
    fetchError.value = true;
  } finally {
    isFetching.value = false;
  }
};

const handleDelete = async id => {
  try {
    await CaptainCustomToolsAPI.delete(id);
    tools.value = tools.value.filter(tool => tool.id !== id);
    useAlert(t('AI_AGENT_SETTINGS.ACTIONS.DELETED'));
  } catch (error) {
    useAlert(t('AI_AGENT_SETTINGS.ACTIONS.DELETE_ERROR'));
  }
};

const handleCreated = () => fetchTools();

const selectTab = tab => {
  activeTab.value = tab;
  if (tab === 'actions' && !tools.value.length) fetchTools();
};

onMounted(() => {
  if (activeTab.value === 'actions') fetchTools();
});
</script>

<template>
  <SettingsLayout>
    <template #header>
      <BaseSettingsHeader
        :title="t('AI_AGENT_SETTINGS.TITLE')"
        :description="t('AI_AGENT_SETTINGS.DESCRIPTION')"
      />
    </template>
    <template #body>
      <div class="flex items-center gap-1 border-b border-n-weak mb-4">
        <button
          type="button"
          class="px-3 py-2 text-sm font-medium border-b-2 -mb-px"
          :class="
            activeTab === 'brain'
              ? 'border-n-brand text-n-slate-12'
              : 'border-transparent text-n-slate-11'
          "
          @click="selectTab('brain')"
        >
          {{ t('AI_AGENT_SETTINGS.BRAIN.TAB_LABEL') }}
        </button>
        <button
          type="button"
          class="px-3 py-2 text-sm font-medium border-b-2 -mb-px"
          :class="
            activeTab === 'knowledge'
              ? 'border-n-brand text-n-slate-12'
              : 'border-transparent text-n-slate-11'
          "
          @click="selectTab('knowledge')"
        >
          {{ t('AI_AGENT_SETTINGS.KNOWLEDGE.TAB_LABEL') }}
        </button>
        <button
          type="button"
          class="px-3 py-2 text-sm font-medium border-b-2 -mb-px"
          :class="
            activeTab === 'actions'
              ? 'border-n-brand text-n-slate-12'
              : 'border-transparent text-n-slate-11'
          "
          @click="selectTab('actions')"
        >
          {{ t('AI_AGENT_SETTINGS.ACTIONS.TAB_LABEL') }}
        </button>
      </div>

      <BusinessBrainPanel v-if="activeTab === 'brain'" />
      <KnowledgeBasePanel v-else-if="activeTab === 'knowledge'" />

      <section v-else class="flex flex-col gap-4 max-w-3xl">
        <div class="flex items-center justify-between">
          <div>
            <h3 class="text-sm font-medium text-n-slate-12">
              {{ t('AI_AGENT_SETTINGS.ACTIONS.TITLE') }}
            </h3>
            <p class="text-xs text-n-slate-11 mt-0.5">
              {{ t('AI_AGENT_SETTINGS.ACTIONS.DESCRIPTION') }}
            </p>
          </div>
          <ButtonV4
            sm
            solid
            blue
            icon="i-lucide-plus"
            :label="t('AI_AGENT_SETTINGS.ACTIONS.ADD_BUTTON')"
            @click="addDialogRef?.open()"
          />
        </div>

        <p v-if="!isFetching && !tools.length" class="text-sm text-n-slate-11">
          {{ t('AI_AGENT_SETTINGS.ACTIONS.EMPTY') }}
        </p>
        <p v-else-if="isFetching" class="text-sm text-n-slate-11">
          {{ t('AI_AGENT_SETTINGS.LOADING') }}
        </p>
        <p v-else-if="fetchError" class="text-sm text-n-ruby-11">
          {{ t('AI_AGENT_SETTINGS.ERRORS.FETCH') }}
        </p>

        <ActionCard
          v-for="tool in tools"
          :key="tool.id"
          :tool="tool"
          @delete="handleDelete"
        />
      </section>

      <AddActionDialog ref="addDialogRef" @created="handleCreated" />
    </template>
  </SettingsLayout>
</template>
