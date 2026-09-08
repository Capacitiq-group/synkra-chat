<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CaptainCustomToolsAPI from 'dashboard/api/captainCustomTools';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import ActionCard from './components/ActionCard.vue';
import AddActionDialog from './components/AddActionDialog.vue';
import ButtonV4 from 'next/button/Button.vue';

const { t } = useI18n();

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

onMounted(fetchTools);
</script>

<template>
  <SettingsLayout
    :is-loading="isFetching"
    :no-records-found="fetchError && !tools.length"
    :loading-message="t('AI_AGENT_SETTINGS.LOADING')"
    :no-records-message="t('AI_AGENT_SETTINGS.ERRORS.FETCH')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('AI_AGENT_SETTINGS.TITLE')"
        :description="t('AI_AGENT_SETTINGS.DESCRIPTION')"
      />
    </template>
    <template #body>
      <section class="flex flex-col gap-4 max-w-3xl">
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
