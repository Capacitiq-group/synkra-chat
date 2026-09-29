<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ButtonV4 from 'next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  planKey: { type: String, required: true },
  name: { type: String, required: true },
  priceZar: { type: Number, required: true },
  priceUsd: { type: Number, required: true },
  // Set when the account is verified for a discount programme:
  // discountedPriceZar/Usd is what this plan costs them, programme is
  // 'student' | 'community' (decides the label).
  discountedPriceZar: { type: Number, default: null },
  discountedPriceUsd: { type: Number, default: null },
  programme: { type: String, default: null },
  // Display-only - the actual Paystack charge is always in ZAR
  // regardless of this (see SynkraSubscription#preferred_currency).
  currency: {
    type: String,
    default: 'zar',
    validator: value => ['zar', 'usd'].includes(value),
  },
  messageAllowance: { type: Number, required: true },
  staffLimit: { type: Number, required: true },
  isCurrent: { type: Boolean, default: false },
  isPending: { type: Boolean, default: false },
  isProcessing: { type: Boolean, default: false },
  // Whether this card's action would be an upgrade (higher rank than
  // the account's current plan) or a downgrade - decides whether we
  // send the customer through real Paystack checkout or just schedule
  // a local plan change for period end.
  action: {
    type: String,
    default: null,
    validator: value => [null, 'upgrade', 'downgrade'].includes(value),
  },
});

const emit = defineEmits(['select']);

const { t } = useI18n();

const isUsd = computed(() => props.currency === 'usd');
const currencySymbol = computed(() => (isUsd.value ? '$' : 'R'));
const basePrice = computed(() =>
  isUsd.value ? props.priceUsd : props.priceZar
);
// null (not 0) when no programme discount applies, so the template's
// v-if checks below still work as "is there a discount to show".
const discountedPrice = computed(() =>
  isUsd.value ? props.discountedPriceUsd : props.discountedPriceZar
);
</script>

<template>
  <div
    class="rounded-xl border p-6 flex flex-col gap-5 min-h-[15rem]"
    :class="
      isCurrent ? 'border-n-brand bg-n-brand/5' : 'border-n-weak bg-n-solid-2'
    "
  >
    <div class="flex items-start justify-between gap-2">
      <div>
        <h3 class="text-lg font-medium text-n-slate-12">{{ name }}</h3>
        <p class="text-base text-n-slate-11 mt-1.5">
          <span v-if="discountedPrice" class="line-through mr-1.5">
            {{
              t('SYNKRA_BILLING_SETTINGS.PLANS.PRICE', {
                symbol: currencySymbol,
                price: basePrice,
              })
            }}
          </span>
          <span :class="{ 'text-n-slate-12 font-medium': discountedPrice }">
            {{
              t('SYNKRA_BILLING_SETTINGS.PLANS.PRICE', {
                symbol: currencySymbol,
                price: discountedPrice || basePrice,
              })
            }}
          </span>
        </p>
        <p v-if="discountedPrice" class="text-xs text-n-teal-11 mt-1">
          {{
            programme === 'community'
              ? t('SYNKRA_BILLING_SETTINGS.PLANS.COMMUNITY_PRICE')
              : t('SYNKRA_BILLING_SETTINGS.PLANS.STUDENT_PRICE')
          }}
        </p>
      </div>
      <span
        v-if="isCurrent"
        class="text-xs font-medium px-2.5 py-1 rounded-md bg-n-teal-3 text-n-teal-11 flex-shrink-0"
      >
        {{ t('SYNKRA_BILLING_SETTINGS.PLANS.CURRENT') }}
      </span>
      <span
        v-else-if="isPending"
        class="text-xs font-medium px-2.5 py-1 rounded-md bg-n-amber-3 text-n-amber-11 flex-shrink-0"
      >
        {{ t('SYNKRA_BILLING_SETTINGS.PLANS.SCHEDULED') }}
      </span>
    </div>
    <ul class="text-sm text-n-slate-11 flex flex-col gap-2.5">
      <li class="flex items-center gap-2.5">
        <Icon icon="i-lucide-message-square" class="size-4 flex-shrink-0" />
        {{
          t('SYNKRA_BILLING_SETTINGS.PLANS.MESSAGE_ALLOWANCE', {
            count: messageAllowance,
          })
        }}
      </li>
      <li class="flex items-center gap-2.5">
        <Icon icon="i-lucide-users" class="size-4 flex-shrink-0" />
        {{
          t('SYNKRA_BILLING_SETTINGS.PLANS.STAFF_LIMIT', {
            count: staffLimit,
          })
        }}
      </li>
    </ul>
    <ButtonV4
      v-if="action"
      :solid="action === 'upgrade'"
      :faded="action === 'downgrade'"
      :blue="action === 'upgrade'"
      :slate="action === 'downgrade'"
      :is-loading="isProcessing"
      class="mt-auto w-full"
      @click="emit('select', planKey)"
    >
      {{
        action === 'upgrade'
          ? t('SYNKRA_BILLING_SETTINGS.PLANS.UPGRADE_BUTTON', { name })
          : t('SYNKRA_BILLING_SETTINGS.PLANS.DOWNGRADE_BUTTON', { name })
      }}
    </ButtonV4>
  </div>
</template>
