<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const emit = defineEmits(['confirm']);

const { t } = useI18n();
const dialogRef = ref(null);

const handleConfirm = () => emit('confirm');

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="t('SYNKRA_BILLING_SETTINGS.CANCEL_DIALOG.TITLE')"
    :description="t('SYNKRA_BILLING_SETTINGS.CANCEL_DIALOG.DESCRIPTION')"
    :confirm-button-label="t('SYNKRA_BILLING_SETTINGS.CANCEL_DIALOG.CONFIRM')"
    :cancel-button-label="t('SYNKRA_BILLING_SETTINGS.CANCEL_DIALOG.DISMISS')"
    @confirm="handleConfirm"
  />
</template>
