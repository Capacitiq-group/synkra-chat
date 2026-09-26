<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import { useAlert } from 'dashboard/composables';
import { useSynkraProgrammes } from 'dashboard/composables/useSynkraProgrammes';
import SynkraCommunityApplicationAPI from 'dashboard/api/synkraCommunityApplication';
import BillingCard from '../../billing/components/BillingCard.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ButtonV4 from 'next/button/Button.vue';

const { t } = useI18n();
const { community: status, fetchProgrammes } = useSynkraProgrammes();

const isLoading = ref(true);
const isWorking = ref(false);
const showForm = ref(false);
const files = ref([]);
const reply = ref('');
const claimCode = ref('');
const isClaiming = ref(false);

const form = reactive({
  organisation_name: '',
  organisation_type: '',
  registration_status: '',
  registration_number: '',
  country: 'South Africa',
  address: '',
  website: '',
  social_url: '',
  general_email: '',
  general_phone: '',
  contact_name: '',
  contact_role: '',
  contact_email: '',
  contact_phone: '',
  account_person: '',
  billing_contact: '',
  organisation_description: '',
  initiative_description: '',
  initiative_serves: '',
  initiative_location: '',
  initiative_frequency: '',
  faith_based: false,
  faith_initiative_benefit: '',
  evidence_links: '',
  no_ai_images: false,
});

const TYPE_OPTIONS = ['NPO', 'NGO', 'NPC', 'CHARITY', 'CBO', 'FAITH', 'OTHER'];
const REGISTRATION_OPTIONS = ['REGISTERED', 'IN_PROGRESS', 'NOT_REGISTERED'];

// [key, control] - control is 'input' or 'textarea'. Grouped to match
// the section headings; labels come from COMMUNITY.FIELDS.<KEY>.
const ORG_FIELDS = [
  ['organisation_name', 'input'],
  ['country', 'input'],
  ['address', 'input'],
  ['website', 'input'],
  ['social_url', 'input'],
  ['general_email', 'input'],
  ['general_phone', 'input'],
  ['organisation_description', 'textarea'],
];
const CONTACT_FIELDS = [
  ['contact_name', 'input'],
  ['contact_role', 'input'],
  ['contact_email', 'input'],
  ['contact_phone', 'input'],
  ['account_person', 'input'],
  ['billing_contact', 'input'],
];
const INITIATIVE_FIELDS = [
  ['initiative_description', 'textarea'],
  ['initiative_serves', 'input'],
  ['initiative_location', 'input'],
  ['initiative_frequency', 'input'],
];

const isVerified = computed(() => !!status.value?.verified);
const review = computed(() => status.value?.review || null);
const isInReview = computed(() => review.value?.status === 'review');
const needsInfo = computed(() => review.value?.status === 'needs_info');

const verifiedUntil = computed(() => {
  const expiresAt = status.value?.expires_at;
  return expiresAt ? format(new Date(expiresAt), 'd MMM yyyy') : '';
});

const fieldLabel = key =>
  t(`SYNKRA_BILLING_SETTINGS.COMMUNITY.FIELDS.${key.toUpperCase()}`);

const errorMessage = error => {
  const errorCode = error?.response?.data?.code;
  const key = errorCode ? errorCode.toUpperCase() : 'GENERIC';
  const path = `SYNKRA_BILLING_SETTINGS.COMMUNITY.ERRORS.${key}`;
  return t(path) === path
    ? t('SYNKRA_BILLING_SETTINGS.COMMUNITY.ERRORS.GENERIC')
    : t(path);
};

const onFilesChosen = event => {
  files.value = Array.from(event.target.files || []);
};

const submit = async () => {
  isWorking.value = true;
  try {
    const response = await SynkraCommunityApplicationAPI.submit(
      { ...form },
      files.value
    );
    status.value = response.data;
    showForm.value = false;
    files.value = [];
    useAlert(t('SYNKRA_BILLING_SETTINGS.COMMUNITY.SUBMITTED'));
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isWorking.value = false;
  }
};

const sendReply = async () => {
  isWorking.value = true;
  try {
    const response = await SynkraCommunityApplicationAPI.addInformation(
      reply.value,
      files.value
    );
    status.value = response.data;
    reply.value = '';
    files.value = [];
    useAlert(t('SYNKRA_BILLING_SETTINGS.COMMUNITY.UPDATED'));
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isWorking.value = false;
  }
};

const claim = async () => {
  if (!claimCode.value.trim()) return;
  isClaiming.value = true;
  try {
    const response = await SynkraCommunityApplicationAPI.claim(
      claimCode.value.trim()
    );
    status.value = response.data;
    claimCode.value = '';
    useAlert(t('SYNKRA_BILLING_SETTINGS.COMMUNITY.CLAIMED'));
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isClaiming.value = false;
  }
};

onMounted(async () => {
  try {
    await fetchProgrammes();
  } finally {
    isLoading.value = false;
  }
});
</script>

<template>
  <BillingCard
    :title="t('SYNKRA_BILLING_SETTINGS.COMMUNITY.TITLE')"
    :description="t('SYNKRA_BILLING_SETTINGS.COMMUNITY.DESCRIPTION')"
  >
    <div v-if="isLoading" class="px-5 text-sm text-n-slate-11">
      {{ t('SYNKRA_BILLING_SETTINGS.LOADING') }}
    </div>

    <div v-else-if="isVerified" class="px-5">
      <p class="text-sm font-medium text-n-slate-12">
        {{
          t('SYNKRA_BILLING_SETTINGS.COMMUNITY.VERIFIED_UNTIL', {
            date: verifiedUntil,
          })
        }}
      </p>
    </div>

    <div v-else-if="isInReview" class="px-5 text-sm text-n-slate-11">
      {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.IN_REVIEW') }}
    </div>

    <div v-else-if="needsInfo" class="px-5 grid gap-3 max-w-2xl">
      <div class="text-sm text-n-slate-12">
        <p class="font-medium">
          {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.NEEDS_INFO') }}
        </p>
        <p class="text-n-slate-11 whitespace-pre-wrap">{{ review.note }}</p>
      </div>
      <label class="grid gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.ADD_INFO_LABEL') }}
        </span>
        <textarea
          v-model="reply"
          rows="4"
          class="rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12"
        />
      </label>
      <input
        type="file"
        multiple
        accept=".pdf,image/jpeg,image/png,image/webp"
        class="text-sm text-n-slate-11"
        @change="onFilesChosen"
      />
      <div>
        <ButtonV4 sm :is-loading="isWorking" @click="sendReply">
          {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.ADD_INFO_SUBMIT') }}
        </ButtonV4>
      </div>
    </div>

    <div v-else-if="!showForm" class="px-5 grid gap-3">
      <div v-if="status?.rejection" class="text-sm text-n-slate-12">
        <p class="font-medium">
          {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.REJECTED') }}
        </p>
        <p class="text-n-slate-11 whitespace-pre-wrap">
          {{ status.rejection.note }}
        </p>
      </div>
      <div>
        <ButtonV4 sm @click="showForm = true">
          {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.APPLY') }}
        </ButtonV4>
      </div>
      <div class="pt-2 border-t border-n-weak grid gap-2 max-w-sm">
        <p class="text-xs text-n-slate-11">
          {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.CLAIM_HELP') }}
        </p>
        <div class="flex items-center gap-2">
          <Input
            v-model="claimCode"
            :placeholder="
              t('SYNKRA_BILLING_SETTINGS.COMMUNITY.CLAIM_PLACEHOLDER')
            "
          />
          <ButtonV4
            sm
            faded
            slate
            :is-loading="isClaiming"
            :disabled="!claimCode.trim()"
            @click="claim"
          >
            {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.CLAIM_SUBMIT') }}
          </ButtonV4>
        </div>
      </div>
    </div>

    <div v-else class="px-5 grid gap-5 max-w-2xl">
      <section class="grid gap-3">
        <h4 class="text-sm font-medium text-n-slate-12">
          {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.SECTION_ORG') }}
        </h4>
        <label class="grid gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ fieldLabel('organisation_type') }}
          </span>
          <select
            v-model="form.organisation_type"
            class="h-10 rounded-lg border border-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12"
          >
            <option value="" disabled>
              {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.SELECT') }}
            </option>
            <option v-for="type in TYPE_OPTIONS" :key="type" :value="type">
              {{ t(`SYNKRA_BILLING_SETTINGS.COMMUNITY.TYPES.${type}`) }}
            </option>
          </select>
        </label>
        <label class="grid gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ fieldLabel('registration_status') }}
          </span>
          <select
            v-model="form.registration_status"
            class="h-10 rounded-lg border border-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12"
          >
            <option value="" disabled>
              {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.SELECT') }}
            </option>
            <option
              v-for="option in REGISTRATION_OPTIONS"
              :key="option"
              :value="option.toLowerCase()"
            >
              {{
                t(`SYNKRA_BILLING_SETTINGS.COMMUNITY.REGISTRATION.${option}`)
              }}
            </option>
          </select>
        </label>
        <Input
          v-if="form.registration_status === 'registered'"
          v-model="form.registration_number"
          :label="fieldLabel('registration_number')"
        />
        <template v-for="[key, control] in ORG_FIELDS" :key="key">
          <Input
            v-if="control === 'input'"
            v-model="form[key]"
            :label="fieldLabel(key)"
          />
          <label v-else class="grid gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ fieldLabel(key) }}
            </span>
            <textarea
              v-model="form[key]"
              rows="3"
              class="rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12"
            />
          </label>
        </template>
      </section>

      <section class="grid gap-3">
        <h4 class="text-sm font-medium text-n-slate-12">
          {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.SECTION_CONTACT') }}
        </h4>
        <Input
          v-for="[key] in CONTACT_FIELDS"
          :key="key"
          v-model="form[key]"
          :label="fieldLabel(key)"
        />
      </section>

      <section class="grid gap-3">
        <h4 class="text-sm font-medium text-n-slate-12">
          {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.SECTION_INITIATIVE') }}
        </h4>
        <template v-for="[key, control] in INITIATIVE_FIELDS" :key="key">
          <Input
            v-if="control === 'input'"
            v-model="form[key]"
            :label="fieldLabel(key)"
          />
          <label v-else class="grid gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ fieldLabel(key) }}
            </span>
            <textarea
              v-model="form[key]"
              rows="3"
              class="rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12"
            />
          </label>
        </template>
        <label class="flex items-start gap-2 text-sm text-n-slate-12">
          <input v-model="form.faith_based" type="checkbox" class="mt-1" />
          <span>{{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.FAITH_BASED') }}</span>
        </label>
        <template v-if="form.faith_based">
          <p class="text-sm text-n-slate-11">
            {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.FAITH_HELP') }}
          </p>
          <label class="grid gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ fieldLabel('faith_initiative_benefit') }}
            </span>
            <textarea
              v-model="form.faith_initiative_benefit"
              rows="3"
              class="rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12"
            />
          </label>
        </template>
      </section>

      <section class="grid gap-3">
        <h4 class="text-sm font-medium text-n-slate-12">
          {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.SECTION_EVIDENCE') }}
        </h4>
        <p class="text-sm text-n-slate-11">
          {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.EVIDENCE_HELP') }}
        </p>
        <label class="grid gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.EVIDENCE_FILES') }}
          </span>
          <input
            type="file"
            multiple
            accept=".pdf,image/jpeg,image/png,image/webp"
            class="text-sm text-n-slate-11"
            @change="onFilesChosen"
          />
        </label>
        <Input
          v-model="form.evidence_links"
          :label="fieldLabel('evidence_links')"
        />
        <label class="flex items-start gap-2 text-sm text-n-slate-12">
          <input v-model="form.no_ai_images" type="checkbox" class="mt-1" />
          <span>{{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.DECLARATION') }}</span>
        </label>
      </section>

      <div class="flex items-center gap-2">
        <ButtonV4 sm :is-loading="isWorking" @click="submit">
          {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.SUBMIT') }}
        </ButtonV4>
        <ButtonV4 sm faded slate @click="showForm = false">
          {{ t('SYNKRA_BILLING_SETTINGS.COMMUNITY.CANCEL') }}
        </ButtonV4>
      </div>
    </div>
  </BillingCard>
</template>
