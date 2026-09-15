import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import SynkraBillingAPI from 'dashboard/api/synkraBilling';

// How many times (and how often) to re-poll GET subscription after a
// Paystack checkout redirect returns, while we wait for Paystack's
// webhook to actually land and flip the local subscription record.
// There's no synchronous verify-and-activate endpoint yet - the
// webhook is the only thing that activates a subscription - so this
// polling is the frontend's only way to notice when that's happened.
const POLL_ATTEMPTS = 8;
const POLL_INTERVAL_MS = 2500;

const subscription = ref(null);
const isFetching = ref(false);
const isProcessing = ref(false);
const fetchError = ref(false);
const isConfirmingPayment = ref(false);

export function useSynkraBilling() {
  const { t } = useI18n();

  const plan = computed(() => subscription.value?.plan);
  const status = computed(() => subscription.value?.status);
  const usage = computed(() => subscription.value?.usage);
  const isPastDue = computed(() => status.value === 'past_due');
  const isRestricted = computed(() => status.value === 'restricted');
  const isCancelled = computed(() => status.value === 'cancelled');
  const isCancelling = computed(
    () => !!subscription.value?.cancel_at_period_end
  );
  const pendingPlan = computed(() => subscription.value?.pending_plan);

  const fetchSubscription = async ({ silent = false } = {}) => {
    if (!silent) isFetching.value = true;
    fetchError.value = false;
    try {
      const response = await SynkraBillingAPI.get();
      subscription.value = response.data;
    } catch (error) {
      fetchError.value = true;
      if (!silent) {
        useAlert(t('SYNKRA_BILLING_SETTINGS.ERRORS.FETCH'));
      }
    } finally {
      if (!silent) isFetching.value = false;
    }
  };

  const buildCallbackUrl = () => {
    // Bring the browser back to this same billing page after Paystack
    // finishes, whatever account/host it's currently on.
    return window.location.href.split('?')[0];
  };

  // Waits for the webhook-driven activation to land, then refreshes
  // one final time. Never throws - if the webhook is slow/misses, the
  // regular fetch on next visit will still pick up the right state.
  const pollForConfirmation = async () => {
    isConfirmingPayment.value = true;
    for (let attempt = 0; attempt < POLL_ATTEMPTS; attempt += 1) {
      // eslint-disable-next-line no-await-in-loop
      await new Promise(resolve => setTimeout(resolve, POLL_INTERVAL_MS));
      // eslint-disable-next-line no-await-in-loop
      await fetchSubscription({ silent: true });
      if (subscription.value?.status === 'active') break;
    }
    isConfirmingPayment.value = false;
  };

  const checkout = async planKey => {
    isProcessing.value = true;
    try {
      const response = await SynkraBillingAPI.checkout(
        planKey,
        buildCallbackUrl()
      );
      window.location.href = response.data.authorization_url;
    } catch (error) {
      const message =
        error.response?.data?.error ||
        t('SYNKRA_BILLING_SETTINGS.ERRORS.CHECKOUT');
      useAlert(message);
      isProcessing.value = false;
    }
  };

  // Schedules a downgrade for the end of the current period (never
  // applied immediately - see SynkraSubscription#change_plan!). Note:
  // this only updates Synkra Chat's own record today, it does not yet
  // call Paystack to reduce what gets charged next cycle - that sync
  // still needs to be built before this is safe to rely on for real
  // billing amounts.
  const scheduleDowngrade = async planKey => {
    isProcessing.value = true;
    try {
      const response = await SynkraBillingAPI.changePlan(planKey);
      subscription.value = response.data;
      useAlert(t('SYNKRA_BILLING_SETTINGS.SUCCESS.PLAN_SCHEDULED'));
    } catch (error) {
      useAlert(t('SYNKRA_BILLING_SETTINGS.ERRORS.CHANGE_PLAN'));
    } finally {
      isProcessing.value = false;
    }
  };

  const cancelSubscription = async () => {
    isProcessing.value = true;
    try {
      const response = await SynkraBillingAPI.cancel();
      subscription.value = response.data;
      useAlert(t('SYNKRA_BILLING_SETTINGS.SUCCESS.CANCELLED'));
    } catch (error) {
      useAlert(t('SYNKRA_BILLING_SETTINGS.ERRORS.CANCEL'));
    } finally {
      isProcessing.value = false;
    }
  };

  const resumeSubscription = async () => {
    isProcessing.value = true;
    try {
      const response = await SynkraBillingAPI.resume();
      subscription.value = response.data;
      useAlert(t('SYNKRA_BILLING_SETTINGS.SUCCESS.RESUMED'));
    } catch (error) {
      useAlert(t('SYNKRA_BILLING_SETTINGS.ERRORS.RESUME'));
    } finally {
      isProcessing.value = false;
    }
  };

  return {
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
  };
}
