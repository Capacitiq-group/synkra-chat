import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';

// "Automations" - the Chat-facing name for the Chat<->Flow bridge. Never
// named "Flow" or "Connect to Flow" anywhere in this UI - see
// docs/synkra/automations-flow-bridge.md for why.
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/automations'),
      meta: {
        permissions: ['administrator'],
      },
      component: SettingsWrapper,
      props: {
        headerTitle: 'AUTOMATIONS_SETTINGS.TITLE',
        icon: 'flash',
        showNewButton: false,
      },
      children: [
        {
          path: '',
          name: 'automations_settings_index',
          component: Index,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
