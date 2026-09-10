<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CaptainAssistantsAPI from 'dashboard/api/captainAssistants';
import CaptainDocumentsAPI from 'dashboard/api/captainDocuments';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import ButtonV4 from 'next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const { t } = useI18n();

const isFetching = ref(true);
const fetchError = ref(false);
const assistantId = ref(null);
const documents = ref([]);

const websiteName = ref('');
const websiteUrl = ref('');
const isAddingWebsite = ref(false);
const manualName = ref('');
const manualContent = ref('');
const isAddingManual = ref(false);
const isUploadingPdf = ref(false);
const fileInputRef = ref(null);
const syncingIds = ref(new Set());

const fetchAll = async () => {
  isFetching.value = true;
  fetchError.value = false;
  try {
    const assistantResponse = await CaptainAssistantsAPI.get();
    const [assistant] = assistantResponse.data.payload;
    assistantId.value = assistant?.id || null;

    if (assistantId.value) {
      const docsResponse = await CaptainDocumentsAPI.get();
      documents.value = docsResponse.data.payload;
    }
  } catch (error) {
    fetchError.value = true;
  } finally {
    isFetching.value = false;
  }
};

const handleAddWebsite = async () => {
  if (!websiteName.value.trim() || !websiteUrl.value.trim()) return;
  isAddingWebsite.value = true;
  try {
    const response = await CaptainDocumentsAPI.create({
      document: {
        name: websiteName.value.trim(),
        external_link: websiteUrl.value.trim(),
        assistant_id: assistantId.value,
      },
    });
    documents.value = [response.data, ...documents.value];
    websiteName.value = '';
    websiteUrl.value = '';
    useAlert(t('AI_AGENT_SETTINGS.KNOWLEDGE.ADDED'));
  } catch (error) {
    useAlert(
      error.response?.data?.message || t('AI_AGENT_SETTINGS.KNOWLEDGE.ADD_ERROR')
    );
  } finally {
    isAddingWebsite.value = false;
  }
};

const isManualDocument = doc =>
  !doc.pdf_document && !!doc.external_link?.startsWith('Manual entry:');

const handleAddManual = async () => {
  if (!manualName.value.trim() || !manualContent.value.trim()) return;
  isAddingManual.value = true;
  try {
    const response = await CaptainDocumentsAPI.create({
      document: {
        name: manualName.value.trim(),
        content: manualContent.value.trim(),
        assistant_id: assistantId.value,
      },
    });
    documents.value = [response.data, ...documents.value];
    manualName.value = '';
    manualContent.value = '';
    useAlert(t('AI_AGENT_SETTINGS.KNOWLEDGE.ADDED'));
  } catch (error) {
    useAlert(
      error.response?.data?.message || t('AI_AGENT_SETTINGS.KNOWLEDGE.ADD_ERROR')
    );
  } finally {
    isAddingManual.value = false;
  }
};

const handleFileSelected = async event => {
  const file = event.target.files?.[0];
  if (!file) return;
  isUploadingPdf.value = true;
  try {
    const formData = new FormData();
    formData.append('document[name]', file.name);
    formData.append('document[assistant_id]', assistantId.value);
    formData.append('document[pdf_file]', file);
    const response = await CaptainDocumentsAPI.create(formData);
    documents.value = [response.data, ...documents.value];
    useAlert(t('AI_AGENT_SETTINGS.KNOWLEDGE.ADDED'));
  } catch (error) {
    useAlert(
      error.response?.data?.message || t('AI_AGENT_SETTINGS.KNOWLEDGE.ADD_ERROR')
    );
  } finally {
    isUploadingPdf.value = false;
    if (fileInputRef.value) fileInputRef.value.value = '';
  }
};

const handleSync = async id => {
  syncingIds.value = new Set([...syncingIds.value, id]);
  try {
    await CaptainDocumentsAPI.sync(id);
    useAlert(t('AI_AGENT_SETTINGS.KNOWLEDGE.SYNC_STARTED'));
  } catch (error) {
    useAlert(t('AI_AGENT_SETTINGS.KNOWLEDGE.SYNC_ERROR'));
  } finally {
    const next = new Set([...syncingIds.value]);
    next.delete(id);
    syncingIds.value = next;
  }
};

const handleDelete = async id => {
  try {
    await CaptainDocumentsAPI.delete(id);
    documents.value = documents.value.filter(doc => doc.id !== id);
    useAlert(t('AI_AGENT_SETTINGS.KNOWLEDGE.DELETED'));
  } catch (error) {
    useAlert(t('AI_AGENT_SETTINGS.KNOWLEDGE.DELETE_ERROR'));
  }
};

onMounted(fetchAll);
</script>

<template>
  <div v-if="isFetching" class="text-sm text-n-slate-11">
    {{ t('AI_AGENT_SETTINGS.LOADING') }}
  </div>
  <p v-else-if="fetchError" class="text-sm text-n-ruby-11">
    {{ t('AI_AGENT_SETTINGS.ERRORS.FETCH') }}
  </p>
  <p v-else-if="!assistantId" class="text-sm text-n-slate-11">
    {{ t('AI_AGENT_SETTINGS.KNOWLEDGE.SET_UP_BRAIN_FIRST') }}
  </p>
  <div v-else class="flex flex-col gap-6 max-w-2xl">
    <div class="flex flex-col gap-2">
      <h3 class="text-sm font-medium text-n-slate-12">
        {{ t('AI_AGENT_SETTINGS.KNOWLEDGE.ADD_WEBSITE_TITLE') }}
      </h3>
      <div class="flex items-end gap-2">
        <Input
          v-model="websiteName"
          :label="t('AI_AGENT_SETTINGS.KNOWLEDGE.NAME_LABEL')"
          :placeholder="t('AI_AGENT_SETTINGS.KNOWLEDGE.NAME_PLACEHOLDER')"
          class="flex-1"
        />
        <Input
          v-model="websiteUrl"
          :label="t('AI_AGENT_SETTINGS.KNOWLEDGE.URL_LABEL')"
          placeholder="https://yourbusiness.com/faq"
          class="flex-1"
        />
        <ButtonV4
          solid
          blue
          :is-loading="isAddingWebsite"
          :label="t('AI_AGENT_SETTINGS.KNOWLEDGE.ADD_BUTTON')"
          @click="handleAddWebsite"
        />
      </div>
      <p class="text-xs text-n-slate-11">
        {{ t('AI_AGENT_SETTINGS.KNOWLEDGE.SYNC_HELP') }}
      </p>
    </div>

    <div class="flex flex-col gap-2">
      <h3 class="text-sm font-medium text-n-slate-12">
        {{ t('AI_AGENT_SETTINGS.KNOWLEDGE.ADD_PDF_TITLE') }}
      </h3>
      <input
        ref="fileInputRef"
        type="file"
        accept="application/pdf"
        class="text-sm text-n-slate-11"
        :disabled="isUploadingPdf"
        @change="handleFileSelected"
      />
    </div>

    <div class="flex flex-col gap-2">
      <h3 class="text-sm font-medium text-n-slate-12">
        {{ t('AI_AGENT_SETTINGS.KNOWLEDGE.ADD_MANUAL_TITLE') }}
      </h3>
      <Input
        v-model="manualName"
        :label="t('AI_AGENT_SETTINGS.KNOWLEDGE.NAME_LABEL')"
        :placeholder="t('AI_AGENT_SETTINGS.KNOWLEDGE.MANUAL_NAME_PLACEHOLDER')"
      />
      <TextArea
        v-model="manualContent"
        :label="t('AI_AGENT_SETTINGS.KNOWLEDGE.MANUAL_CONTENT_LABEL')"
        :placeholder="t('AI_AGENT_SETTINGS.KNOWLEDGE.MANUAL_CONTENT_PLACEHOLDER')"
        :max-length="200000"
        show-character-count
        auto-height
        min-height="6rem"
        max-height="16rem"
      />
      <ButtonV4
        solid
        blue
        class="self-start"
        :is-loading="isAddingManual"
        :label="t('AI_AGENT_SETTINGS.KNOWLEDGE.ADD_BUTTON')"
        @click="handleAddManual"
      />
    </div>

    <div class="flex flex-col gap-2">
      <h3 class="text-sm font-medium text-n-slate-12">
        {{ t('AI_AGENT_SETTINGS.KNOWLEDGE.LIST_TITLE') }}
      </h3>
      <p v-if="!documents.length" class="text-sm text-n-slate-11">
        {{ t('AI_AGENT_SETTINGS.KNOWLEDGE.EMPTY') }}
      </p>
      <div
        v-for="doc in documents"
        :key="doc.id"
        class="flex items-center justify-between gap-4 p-3 rounded-xl border border-n-weak bg-n-solid-2"
      >
        <div class="flex items-start gap-3 min-w-0">
          <Icon
            :icon="
              doc.pdf_document
                ? 'i-lucide-file-text'
                : isManualDocument(doc)
                  ? 'i-lucide-pencil'
                  : 'i-lucide-globe'
            "
            class="size-5 flex-shrink-0 mt-0.5"
          />
          <div class="min-w-0">
            <p class="text-sm font-medium text-n-slate-12 truncate">
              {{ doc.name }}
            </p>
            <p class="text-xs text-n-slate-11 truncate">
              {{
                doc.pdf_document
                  ? t('AI_AGENT_SETTINGS.KNOWLEDGE.PDF_LABEL')
                  : isManualDocument(doc)
                    ? t('AI_AGENT_SETTINGS.KNOWLEDGE.MANUAL_LABEL')
                    : doc.external_link
              }}
              <span v-if="doc.sync_status"> &middot; {{ doc.sync_status }}</span>
            </p>
          </div>
        </div>
        <div class="flex items-center gap-2 flex-shrink-0">
          <ButtonV4
            v-if="doc.external_link && !isManualDocument(doc)"
            sm
            faded
            slate
            icon="i-lucide-refresh-cw"
            :is-loading="syncingIds.has(doc.id)"
            :disabled="doc.sync_in_progress"
            :label="t('AI_AGENT_SETTINGS.KNOWLEDGE.SYNC_BUTTON')"
            @click="handleSync(doc.id)"
          />
          <ButtonV4
            sm
            faded
            ruby
            icon="i-lucide-trash-2"
            :label="t('AI_AGENT_SETTINGS.ACTIONS.DELETE_BUTTON')"
            @click="handleDelete(doc.id)"
          />
        </div>
      </div>
    </div>
  </div>
</template>
