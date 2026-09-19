import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';

// Synkra Chat's own billing settings page - separate from (and
// replaces the nav entry for) Chatwoot's own cloud-only billing page
// at settings/billing, which stays hidden per Sidebar.vue. This one
// isn't gated to installationTypes.CLOUD since Synkra Chat is
// self-hosted.
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/synkra-billing'),
      meta: {
        permissions: ['administrator'],
      },
      component: SettingsWrapper,
      props: {
        headerTitle: 'SYNKRA_BILLING_SETTINGS.TITLE',
        icon: 'credit-card-person',
        showNewButton: false,
      },
      children: [
        {
          path: '',
          name: 'synkra_billing_settings_index',
          component: Index,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
