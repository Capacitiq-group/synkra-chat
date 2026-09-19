<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  // 'seats' | 'storage' | 'messages' - each has different pricing/input shape
  type: { type: String, required: true },
  packs: { type: Array, default: () => [] }, // only used for type === 'messages'
  // Async function that actually performs the purchase - a prop
  // rather than an emit, since Vue's emit() has no return value to
  // await: a plain emit here would close the dialog and clear the
  // loading state before the real API call even resolved, and any
  // error it threw would be unreachable from this component's
  // try/catch.
  onPurchase: { type: Function, required: true },
});

const { t } = useI18n();
const dialogRef = ref(null);
const quantity = ref(1);
const selectedPackKey = ref(props.packs[0]?.key);
const isPurchasing = ref(false);

const copy = computed(() => ({
  seats: {
    title: t('SYNKRA_BILLING_SETTINGS.ADDONS.SEATS.TITLE'),
    description: t('SYNKRA_BILLING_SETTINGS.ADDONS.SEATS.DESCRIPTION'),
    unit: t('SYNKRA_BILLING_SETTINGS.ADDONS.SEATS.UNIT'),
  },
  storage: {
    title: t('SYNKRA_BILLING_SETTINGS.ADDONS.STORAGE.TITLE'),
    description: t('SYNKRA_BILLING_SETTINGS.ADDONS.STORAGE.DESCRIPTION'),
    unit: t('SYNKRA_BILLING_SETTINGS.ADDONS.STORAGE.UNIT'),
  },
  messages: {
    title: t('SYNKRA_BILLING_SETTINGS.ADDONS.MESSAGES.TITLE'),
    description: t('SYNKRA_BILLING_SETTINGS.ADDONS.MESSAGES.DESCRIPTION'),
  },
}[props.type]));

const handlePurchase = async () => {
  isPurchasing.value = true;
  try {
    if (props.type === 'messages') {
      await props.onPurchase({ packKey: selectedPackKey.value });
    } else {
      await props.onPurchase({ quantity: quantity.value });
    }
    dialogRef.value?.close();
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        t('SYNKRA_BILLING_SETTINGS.ADDONS.PURCHASE_FAILED')
    );
  } finally {
    isPurchasing.value = false;
  }
};

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="copy.title"
    :description="copy.description"
    :confirm-button-label="t('SYNKRA_BILLING_SETTINGS.ADDONS.BUY')"
    :is-loading="isPurchasing"
    @confirm="handlePurchase"
  >
    <div v-if="type === 'messages'" class="grid gap-2 px-1">
      <label
        v-for="pack in packs"
        :key="pack.key"
        class="flex items-center gap-2 p-2 rounded-lg border border-n-weak cursor-pointer"
        :class="{ 'border-n-brand': selectedPackKey === pack.key }"
      >
        <input
          v-model="selectedPackKey"
          type="radio"
          :value="pack.key"
          name="message-pack"
        />
        <span class="text-sm">
          {{ pack.units.toLocaleString() }} {{ t('SYNKRA_BILLING_SETTINGS.ADDONS.MESSAGES.UNIT') }}
          — R{{ pack.price_zar }}
        </span>
      </label>
    </div>
    <div v-else class="px-1">
      <Input
        v-model.number="quantity"
        type="number"
        min="1"
        :label="copy.unit"
      />
    </div>
  </Dialog>
</template>
