<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import { useAlert } from 'dashboard/composables';
import { useSynkraProgrammes } from 'dashboard/composables/useSynkraProgrammes';
import SynkraStudentVerificationAPI from 'dashboard/api/synkraStudentVerification';
import BillingCard from '../../billing/components/BillingCard.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ButtonV4 from 'next/button/Button.vue';

const { t } = useI18n();
const { student: status, fetchProgrammes } = useSynkraProgrammes();

const isLoading = ref(true);
const isWorking = ref(false);

const localPart = ref('');
const institution = ref('');
const extension = ref('');
const code = ref('');
const files = ref([]);
// 'email' | 'document'
const mode = ref('email');
// Set when the person clicks "Use a different email" so the form
// shows again even while a code is still pending for the old address.
const editingEmail = ref(false);

const now = ref(Date.now());
let ticker = null;
let tick = 0;

const extensions = computed(() => status.value?.extensions || []);
const isVerified = computed(() => !!status.value?.verified);
const review = computed(() => status.value?.review || null);
const isInReview = computed(() => review.value?.status === 'review');
const needsInfo = computed(() => review.value?.status === 'needs_info');
const hasPendingCode = computed(
  () => !!status.value?.pending_email && !editingEmail.value && !review.value
);

const verifiedUntil = computed(() => {
  const expiresAt = status.value?.expires_at;
  return expiresAt ? format(new Date(expiresAt), 'd MMM yyyy') : '';
});

const resendSeconds = computed(() => {
  const availableAt = status.value?.resend_available_at;
  if (!availableAt) return 0;
  return Math.max(0, Math.ceil((new Date(availableAt) - now.value) / 1000));
});

const canSend = computed(
  () =>
    localPart.value.trim() &&
    institution.value.trim() &&
    extension.value &&
    !isWorking.value
);
const canConfirm = computed(
  () =>
    code.value.trim().length === (status.value?.otp_length || 6) &&
    !isWorking.value
);
const canUpload = computed(() => files.value.length > 0 && !isWorking.value);

const errorMessage = error => {
  const errorCode = error?.response?.data?.code;
  const key = errorCode ? errorCode.toUpperCase() : 'GENERIC';
  const path = `SYNKRA_BILLING_SETTINGS.STUDENT.ERRORS.${key}`;
  return t(path) === path
    ? t('SYNKRA_BILLING_SETTINGS.STUDENT.ERRORS.GENERIC')
    : t(path);
};

const refresh = async () => {
  try {
    await fetchProgrammes();
  } finally {
    isLoading.value = false;
  }
};

const sendCode = async () => {
  if (!canSend.value) return;
  isWorking.value = true;
  try {
    const response = await SynkraStudentVerificationAPI.sendCode({
      localPart: localPart.value.trim(),
      institution: institution.value.trim(),
      extension: extension.value,
    });
    status.value = response.data;
    editingEmail.value = false;
    code.value = '';
    useAlert(
      t('SYNKRA_BILLING_SETTINGS.STUDENT.CODE_SENT', {
        email: status.value.pending_email,
      })
    );
  } catch (error) {
    useAlert(errorMessage(error));
    // A cooldown response still means a code is already on its way.
    if (error?.response?.data?.code === 'cooldown') await refresh();
  } finally {
    isWorking.value = false;
  }
};

const resendCode = async () => {
  if (resendSeconds.value > 0 || isWorking.value) return;
  const pendingEmail = status.value?.pending_email || '';
  const [address, domain] = pendingEmail.split('@');
  if (!address || !domain) return;
  const matched = extensions.value.find(ext => domain.endsWith(`.${ext}`));
  if (!matched) return;
  isWorking.value = true;
  try {
    const response = await SynkraStudentVerificationAPI.sendCode({
      localPart: address,
      institution: domain.slice(0, -(matched.length + 1)),
      extension: matched,
    });
    status.value = response.data;
    code.value = '';
    useAlert(
      t('SYNKRA_BILLING_SETTINGS.STUDENT.CODE_SENT', {
        email: status.value.pending_email,
      })
    );
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isWorking.value = false;
  }
};

const confirmCode = async () => {
  if (!canConfirm.value) return;
  isWorking.value = true;
  try {
    const response = await SynkraStudentVerificationAPI.confirm(
      code.value.trim()
    );
    status.value = response.data;
    code.value = '';
    useAlert(t('SYNKRA_BILLING_SETTINGS.STUDENT.SUCCESS'));
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isWorking.value = false;
  }
};

const onFilesChosen = event => {
  files.value = Array.from(event.target.files || []);
};

const uploadDocuments = async () => {
  if (!canUpload.value) return;
  isWorking.value = true;
  try {
    const response = await SynkraStudentVerificationAPI.uploadDocuments(
      files.value
    );
    status.value = response.data;
    files.value = [];
    useAlert(t('SYNKRA_BILLING_SETTINGS.STUDENT.DOCUMENT_UPLOADED'));
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isWorking.value = false;
  }
};

const useDifferentEmail = () => {
  editingEmail.value = true;
  code.value = '';
};

onMounted(() => {
  refresh();
  ticker = setInterval(() => {
    now.value = Date.now();
    tick += 1;
    // A document is usually read within a minute or two - keep the
    // card fresh (for up to ~5 minutes) while it's being checked.
    if (isInReview.value && tick % 10 === 0 && tick <= 300) fetchProgrammes();
  }, 1000);
});

onBeforeUnmount(() => {
  if (ticker) clearInterval(ticker);
});
</script>

<template>
  <BillingCard
    :title="t('SYNKRA_BILLING_SETTINGS.STUDENT.TITLE')"
    :description="t('SYNKRA_BILLING_SETTINGS.STUDENT.DESCRIPTION')"
  >
    <div v-if="isLoading" class="px-5 text-sm text-n-slate-11">
      {{ t('SYNKRA_BILLING_SETTINGS.LOADING') }}
    </div>

    <div v-else-if="isVerified" class="px-5 grid gap-1">
      <p class="text-sm font-medium text-n-slate-12">
        {{
          t('SYNKRA_BILLING_SETTINGS.STUDENT.VERIFIED_UNTIL', {
            date: verifiedUntil,
          })
        }}
      </p>
      <p v-if="status.verified_email" class="text-sm text-n-slate-11">
        {{ status.verified_email }}
      </p>
    </div>

    <div v-else-if="isInReview" class="px-5 text-sm text-n-slate-11">
      {{ t('SYNKRA_BILLING_SETTINGS.STUDENT.IN_REVIEW') }}
    </div>

    <div v-else-if="hasPendingCode" class="px-5 grid gap-3 max-w-md">
      <p class="text-sm text-n-slate-11">
        {{
          t('SYNKRA_BILLING_SETTINGS.STUDENT.CODE_SENT', {
            email: status.pending_email,
          })
        }}
      </p>
      <Input
        v-model="code"
        :label="t('SYNKRA_BILLING_SETTINGS.STUDENT.CODE_LABEL')"
        :placeholder="t('SYNKRA_BILLING_SETTINGS.STUDENT.CODE_PLACEHOLDER')"
      />
      <div class="flex flex-wrap items-center gap-2">
        <ButtonV4
          sm
          :is-loading="isWorking"
          :disabled="!canConfirm"
          @click="confirmCode"
        >
          {{ t('SYNKRA_BILLING_SETTINGS.STUDENT.VERIFY') }}
        </ButtonV4>
        <ButtonV4
          sm
          faded
          slate
          :disabled="resendSeconds > 0 || isWorking"
          @click="resendCode"
        >
          {{
            resendSeconds > 0
              ? t('SYNKRA_BILLING_SETTINGS.STUDENT.RESEND_IN', {
                  seconds: resendSeconds,
                })
              : t('SYNKRA_BILLING_SETTINGS.STUDENT.RESEND')
          }}
        </ButtonV4>
        <ButtonV4 sm link slate @click="useDifferentEmail">
          {{ t('SYNKRA_BILLING_SETTINGS.STUDENT.CHANGE_EMAIL') }}
        </ButtonV4>
      </div>
    </div>

    <div v-else class="px-5 grid gap-3">
      <div v-if="needsInfo" class="text-sm text-n-slate-12">
        <p class="font-medium">
          {{ t('SYNKRA_BILLING_SETTINGS.STUDENT.NEEDS_INFO') }}
        </p>
        <p class="text-n-slate-11 whitespace-pre-wrap">{{ review.note }}</p>
      </div>
      <div v-else-if="status?.rejection" class="text-sm text-n-slate-12">
        <p class="font-medium">
          {{ t('SYNKRA_BILLING_SETTINGS.STUDENT.REJECTED') }}
        </p>
        <p class="text-n-slate-11 whitespace-pre-wrap">
          {{ status.rejection.note }}
        </p>
      </div>

      <template v-if="mode === 'email' && !needsInfo">
        <div class="grid sm:grid-cols-[1fr_auto_1fr_auto] items-end gap-2">
          <Input
            v-model="localPart"
            :label="t('SYNKRA_BILLING_SETTINGS.STUDENT.NUMBER_LABEL')"
            :placeholder="
              t('SYNKRA_BILLING_SETTINGS.STUDENT.NUMBER_PLACEHOLDER')
            "
          />
          <span class="hidden sm:block pb-2 text-n-slate-11">@</span>
          <Input
            v-model="institution"
            :label="t('SYNKRA_BILLING_SETTINGS.STUDENT.INSTITUTION_LABEL')"
            :placeholder="
              t('SYNKRA_BILLING_SETTINGS.STUDENT.INSTITUTION_PLACEHOLDER')
            "
          />
          <label class="grid gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('SYNKRA_BILLING_SETTINGS.STUDENT.ENDING_LABEL') }}
            </span>
            <select
              v-model="extension"
              class="h-10 rounded-lg border border-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12"
            >
              <option value="" disabled>
                {{ t('SYNKRA_BILLING_SETTINGS.STUDENT.ENDING_PLACEHOLDER') }}
              </option>
              <option v-for="ext in extensions" :key="ext" :value="ext">
                .{{ ext }}
              </option>
            </select>
          </label>
        </div>
        <div class="flex flex-wrap items-center gap-3">
          <ButtonV4
            sm
            :is-loading="isWorking"
            :disabled="!canSend"
            @click="sendCode"
          >
            {{ t('SYNKRA_BILLING_SETTINGS.STUDENT.SEND_CODE') }}
          </ButtonV4>
          <ButtonV4 sm link slate @click="mode = 'document'">
            {{ t('SYNKRA_BILLING_SETTINGS.STUDENT.NOT_LISTED') }}
          </ButtonV4>
        </div>
      </template>

      <template v-else>
        <p class="text-sm text-n-slate-11 max-w-2xl">
          {{ t('SYNKRA_BILLING_SETTINGS.STUDENT.DOCUMENT_HELP') }}
        </p>
        <label class="grid gap-1 max-w-md">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('SYNKRA_BILLING_SETTINGS.STUDENT.DOCUMENT_FILES') }}
          </span>
          <input
            type="file"
            multiple
            accept=".pdf,image/jpeg,image/png,image/webp"
            class="text-sm text-n-slate-11"
            @change="onFilesChosen"
          />
        </label>
        <div class="flex flex-wrap items-center gap-3">
          <ButtonV4
            sm
            :is-loading="isWorking"
            :disabled="!canUpload"
            @click="uploadDocuments"
          >
            {{ t('SYNKRA_BILLING_SETTINGS.STUDENT.DOCUMENT_UPLOAD') }}
          </ButtonV4>
          <ButtonV4 v-if="!needsInfo" sm link slate @click="mode = 'email'">
            {{ t('SYNKRA_BILLING_SETTINGS.STUDENT.USE_EMAIL') }}
          </ButtonV4>
        </div>
      </template>
    </div>
  </BillingCard>
</template>
