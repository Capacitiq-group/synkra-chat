<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';

import { useSynkraBilling } from 'dashboard/composables/useSynkraBilling';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BillingCard from '../billing/components/BillingCard.vue';
import BillingHeader from '../billing/components/BillingHeader.vue';
import DetailItem from '../billing/components/DetailItem.vue';
import BillingMeter from '../billing/components/BillingMeter.vue';
import PlanCard from './components/PlanCard.vue';
import CancelSubscriptionDialog from './components/CancelSubscriptionDialog.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import ButtonV4 from 'next/button/Button.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const {
  subscription,
  plan,
  status,
  usage,
  isPastDue,
  isRestricted,
  isCancelled,
  isCancelling,
  pendingPlan,
  isFetching,
  isProcessing,
  isConfirmingPayment,
  fetchError,
  fetchSubscription,
  pollForConfirmation,
  checkout,
  scheduleDowngrade,
  cancelSubscription,
  resumeSubscription,
} = useSynkraBilling();

const cancelDialogRef = ref(null);

// Mirrors app/models/synkra_plan.rb - there's no API endpoint that
// lists all plans (only the account's own current one), so a small
// static catalogue here is simpler than building one. IMPORTANT:
// prices/codes come from the real Plan objects on Paystack's own
// dashboard (source of truth) - keep these in sync with synkra_plan.rb.
// This duplication is a real drift risk - currently in sync (checked
// 13 Sep 2026) but nothing enforces that.
// Message/seat numbers are STILL unconfirmed placeholders (Refilwe
// confirmed "we cap volume, not features" but hasn't given exact
// numbers per tier) - see synkra_plan.rb's header comment. CORRECTED
// 13 Sep 2026: they ARE enforced now (backend, since the 12 Sep
// "Enforce message and seat limits per plan" commit - not yet
// deployed as of this comment) - this comment previously said
// otherwise and was stale.
const PLAN_CATALOGUE = [
  {
    key: 'free',
    name: t('SYNKRA_BILLING_SETTINGS.PLANS.FREE_NAME'),
    priceZar: 0,
    messageAllowance: 100,
    staffLimit: 1,
  },
  {
    key: 'starter',
    name: t('SYNKRA_BILLING_SETTINGS.PLANS.STARTER_NAME'),
    priceZar: 299,
    messageAllowance: 1000,
    staffLimit: 5,
  },
  {
    key: 'business',
    name: t('SYNKRA_BILLING_SETTINGS.PLANS.BUSINESS_NAME'),
    priceZar: 599,
    messageAllowance: 4000,
    staffLimit: 15,
  },
  {
    key: 'pro',
    name: t('SYNKRA_BILLING_SETTINGS.PLANS.PRO_NAME'),
    priceZar: 999,
    messageAllowance: 10000,
    staffLimit: 30,
  },
];

const planRank = key => PLAN_CATALOGUE.findIndex(p => p.key === key);

const actionFor = key => {
  if (key === plan.value) return null;
  return planRank(key) > planRank(plan.value) ? 'upgrade' : 'downgrade';
};

const currentPeriodEnd = computed(() => {
  if (!subscription.value?.current_period_end) return '';
  return format(new Date(subscription.value.current_period_end), 'dd MMM, yyyy');
});

const statusBannerColor = computed(() => {
  if (isRestricted.value || isCancelled.value) return 'ruby';
  if (isPastDue.value) return 'amber';
  if (isCancelling.value) return 'amber';
  return null;
});

const statusBannerText = computed(() => {
  if (isRestricted.value) return t('SYNKRA_BILLING_SETTINGS.STATUS.RESTRICTED');
  if (isCancelled.value) return t('SYNKRA_BILLING_SETTINGS.STATUS.CANCELLED');
  if (isPastDue.value) return t('SYNKRA_BILLING_SETTINGS.STATUS.PAST_DUE');
  if (isCancelling.value) {
    return t('SYNKRA_BILLING_SETTINGS.STATUS.CANCELLING', {
      date: currentPeriodEnd.value,
    });
  }
  return '';
});

const handlePlanSelect = planKey => {
  const action = actionFor(planKey);
  if (action === 'upgrade') {
    checkout(planKey);
  } else if (action === 'downgrade') {
    scheduleDowngrade(planKey);
  }
};

const handleCancelClick = () => cancelDialogRef.value?.dialogRef?.open();
const handleCancelConfirm = () => {
  cancelDialogRef.value?.dialogRef?.close();
  cancelSubscription();
};

onMounted(async () => {
  const hasPaystackReference = !!(
    route.query.reference || route.query.trxref
  );

  await fetchSubscription();

  if (hasPaystackReference) {
    // Clean the reference out of the URL so a refresh doesn't re-poll.
    router.replace({ query: {} });
    pollForConfirmation();
  }
});
</script>

<template>
  <SettingsLayout
    :is-loading="isFetching"
    :no-records-found="fetchError && !subscription"
    :loading-message="t('SYNKRA_BILLING_SETTINGS.LOADING')"
    :no-records-message="t('SYNKRA_BILLING_SETTINGS.ERRORS.FETCH')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('SYNKRA_BILLING_SETTINGS.TITLE')"
        :description="t('SYNKRA_BILLING_SETTINGS.DESCRIPTION')"
      />
    </template>
    <template #body>
      <section class="grid gap-4 max-w-6xl">
        <Banner
          v-if="isConfirmingPayment"
          color="blue"
        >
          {{ t('SYNKRA_BILLING_SETTINGS.CONFIRMING_PAYMENT') }}
        </Banner>
        <Banner v-else-if="statusBannerColor" :color="statusBannerColor">
          {{ statusBannerText }}
          <template v-if="isCancelling">
            <button class="link underline" @click="resumeSubscription">
              {{ t('SYNKRA_BILLING_SETTINGS.STATUS.RESUME_LINK') }}
            </button>
          </template>
        </Banner>

        <BillingCard
          :title="t('SYNKRA_BILLING_SETTINGS.CURRENT_PLAN.TITLE')"
          :description="t('SYNKRA_BILLING_SETTINGS.CURRENT_PLAN.DESCRIPTION')"
        >
          <template v-if="!isCancelled && !isCancelling" #action>
            <ButtonV4
              sm
              faded
              ruby
              :is-loading="isProcessing"
              @click="handleCancelClick"
            >
              {{ t('SYNKRA_BILLING_SETTINGS.CANCEL_BUTTON') }}
            </ButtonV4>
          </template>
          <div
            class="grid lg:grid-cols-4 sm:grid-cols-3 grid-cols-1 gap-2 divide-x divide-n-weak"
          >
            <DetailItem
              :label="t('SYNKRA_BILLING_SETTINGS.CURRENT_PLAN.PLAN')"
              :value="subscription?.plan_name || ''"
            />
            <DetailItem
              :label="t('SYNKRA_BILLING_SETTINGS.CURRENT_PLAN.STATUS')"
              :value="status || ''"
            />
            <DetailItem
              v-if="currentPeriodEnd"
              :label="t('SYNKRA_BILLING_SETTINGS.CURRENT_PLAN.RENEWS_ON')"
              :value="currentPeriodEnd"
            />
            <DetailItem
              v-if="pendingPlan"
              :label="t('SYNKRA_BILLING_SETTINGS.CURRENT_PLAN.SWITCHING_TO')"
              :value="pendingPlan"
            />
          </div>
          <div v-if="usage" class="px-5">
            <BillingMeter
              :title="t('SYNKRA_BILLING_SETTINGS.USAGE.MESSAGES')"
              :consumed="usage.business_initiated_messages_used"
              :total-count="usage.business_initiated_message_allowance"
            />
          </div>
        </BillingCard>

        <BillingHeader
          class="px-1 mt-2"
          :title="t('SYNKRA_BILLING_SETTINGS.PLANS.TITLE')"
          :description="t('SYNKRA_BILLING_SETTINGS.PLANS.DESCRIPTION')"
        />
        <div class="grid sm:grid-cols-2 xl:grid-cols-4 gap-5">
          <PlanCard
            v-for="planOption in PLAN_CATALOGUE"
            :key="planOption.key"
            :plan-key="planOption.key"
            :name="planOption.name"
            :price-zar="planOption.priceZar"
            :message-allowance="planOption.messageAllowance"
            :staff-limit="planOption.staffLimit"
            :is-current="planOption.key === plan"
            :is-pending="planOption.key === pendingPlan"
            :is-processing="isProcessing"
            :action="actionFor(planOption.key)"
            @select="handlePlanSelect"
          />
        </div>
      </section>

      <CancelSubscriptionDialog
        ref="cancelDialogRef"
        @confirm="handleCancelConfirm"
      />
    </template>
  </SettingsLayout>
</template>
