import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';

// Synkra AI Agent settings - a friendly front end over Captain (v1)
// and its custom_tools API. Deliberately its own route/nav entry, not
// a re-exposure of Chatwoot's native Captain settings pages (which
// stay hidden - see Sidebar.vue's isCaptainVisibleInV1).
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/ai-agent'),
      meta: {
        permissions: ['administrator'],
      },
      component: SettingsWrapper,
      props: {
        headerTitle: 'AI_AGENT_SETTINGS.TITLE',
        icon: 'bot',
        showNewButton: false,
      },
      children: [
        {
          path: '',
          name: 'ai_agent_settings_index',
          component: Index,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
