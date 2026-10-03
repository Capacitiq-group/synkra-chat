<script setup>
import { onMounted } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAutomations } from 'dashboard/composables/useAutomations';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BillingCard from '../billing/components/BillingCard.vue';
import BillingMeter from '../billing/components/BillingMeter.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';

const { t } = useI18n();

const {
  aiOps,
  emails,
  isProvisioning,
  isReady,
  isFetching,
  fetchError,
  loadCredits,
} = useAutomations();

onMounted(loadCredits);
</script>

<template>
  <SettingsLayout
    :is-loading="isFetching"
    :no-records-found="fetchError"
    :loading-message="t('AUTOMATIONS_SETTINGS.LOADING')"
    :no-records-message="t('AUTOMATIONS_SETTINGS.ERRORS.FETCH')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('AUTOMATIONS_SETTINGS.TITLE')"
        :description="t('AUTOMATIONS_SETTINGS.DESCRIPTION')"
      />
    </template>
    <template #body>
      <section class="grid gap-4 max-w-6xl">
        <Banner v-if="isProvisioning" color="blue">
          {{ t('AUTOMATIONS_SETTINGS.PROVISIONING') }}
        </Banner>

        <BillingCard
          v-if="isReady"
          :title="t('AUTOMATIONS_SETTINGS.USAGE.TITLE')"
          :description="t('AUTOMATIONS_SETTINGS.USAGE.DESCRIPTION')"
        >
          <div class="grid gap-4 px-5 py-2">
            <template v-if="aiOps.included > 0">
              <BillingMeter
                :title="t('AUTOMATIONS_SETTINGS.USAGE.AI_OPS')"
                :consumed="aiOps.used"
                :total-count="aiOps.included"
              />
            </template>
            <p v-else class="text-sm text-n-slate-11">
              {{ t('AUTOMATIONS_SETTINGS.USAGE.AI_OPS_ADDON_ONLY') }}
            </p>

            <template v-if="emails.included > 0">
              <BillingMeter
                :title="t('AUTOMATIONS_SETTINGS.USAGE.EMAILS')"
                :consumed="emails.used"
                :total-count="emails.included"
              />
            </template>
            <p v-else class="text-sm text-n-slate-11">
              {{ t('AUTOMATIONS_SETTINGS.USAGE.EMAILS_ADDON_ONLY') }}
            </p>
          </div>
        </BillingCard>
      </section>
    </template>
  </SettingsLayout>
</template>
