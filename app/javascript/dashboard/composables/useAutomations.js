import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AutomationsAPI from 'dashboard/api/automations';

// Provisioning (Automations::ProvisionFlowJob on the Rails side) is
// async and happens once, right after account creation - a genuinely
// brand-new account can hit the "still provisioning" state for real,
// not just in theory. Poll briefly rather than showing an error.
const PROVISIONING_POLL_ATTEMPTS = 6;
const PROVISIONING_POLL_INTERVAL_MS = 3000;

const credits = ref(null);
const status = ref(null); // 'provisioning' | 'ready' | 'error' | null (not yet fetched)
const isFetching = ref(false);
const fetchError = ref(false);

export function useAutomations() {
  const { t } = useI18n();

  const tier = computed(() => credits.value?.tier);
  const aiOps = computed(() => credits.value?.ai_ops);
  const emails = computed(() => credits.value?.emails);
  const isProvisioning = computed(() => status.value === 'provisioning');
  const isReady = computed(() => status.value === 'ready');

  const fetchCredits = async ({ silent = false } = {}) => {
    if (!silent) isFetching.value = true;
    fetchError.value = false;
    try {
      const response = await AutomationsAPI.get();
      status.value = response.data.status;
      if (status.value === 'ready') {
        credits.value = response.data;
      }
    } catch (error) {
      fetchError.value = true;
      status.value = 'error';
      if (!silent) {
        useAlert(t('AUTOMATIONS_SETTINGS.ERRORS.FETCH'));
      }
    } finally {
      if (!silent) isFetching.value = false;
    }
  };

  // Never throws - if provisioning is still pending after all attempts,
  // the page simply keeps showing the "setting up" state, which is
  // accurate, and a manual refresh will pick it up whenever it lands.
  const pollWhileProvisioning = async () => {
    for (let attempt = 0; attempt < PROVISIONING_POLL_ATTEMPTS; attempt += 1) {
      if (status.value !== 'provisioning') break;
      // eslint-disable-next-line no-await-in-loop
      await new Promise(resolve => {
        setTimeout(resolve, PROVISIONING_POLL_INTERVAL_MS);
      });
      // eslint-disable-next-line no-await-in-loop
      await fetchCredits({ silent: true });
    }
  };

  const loadCredits = async () => {
    await fetchCredits();
    if (status.value === 'provisioning') {
      pollWhileProvisioning();
    }
  };

  return {
    credits,
    status,
    tier,
    aiOps,
    emails,
    isProvisioning,
    isReady,
    isFetching,
    fetchError,
    loadCredits,
  };
}
