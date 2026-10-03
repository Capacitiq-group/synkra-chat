// Presets for Synkra Chat's 'AI Agent > Actions' UI. Each preset is a
// friendly front for creating a Captain::CustomTool: the user only
// ever sees a name, a short description, and a webhook URL to paste
// in from Flow - param_schema (what data the AI collects before
// calling the tool) and the description shown to the LLM come from
// here, not from the user typing JSON.
//
// method is always POST: every one of these sends data *to* a Flow
// webhook trigger, never reads data back for the AI to use, so GET
// isn't offered as an option in the simple picker.
export const ACTION_PRESETS = [
  {
    key: 'trigger_flow',
    icon: 'i-lucide-workflow',
    titleKey: 'AI_AGENT_SETTINGS.PRESETS.TRIGGER_FLOW.TITLE',
    descriptionKey: 'AI_AGENT_SETTINGS.PRESETS.TRIGGER_FLOW.DESCRIPTION',
    toolDescription:
      'Trigger a Synkra Flow workflow for this conversation. Use when the customer asks for something that a configured automation should handle.',
    paramSchema: [],
  },
  {
    key: 'send_email',
    icon: 'i-lucide-mail',
    titleKey: 'AI_AGENT_SETTINGS.PRESETS.SEND_EMAIL.TITLE',
    descriptionKey: 'AI_AGENT_SETTINGS.PRESETS.SEND_EMAIL.DESCRIPTION',
    toolDescription:
      'Send an email on the customer\'s behalf (e.g. an invoice, a quote, a confirmation). Collect the recipient, subject, and body before calling this.',
    paramSchema: [
      { name: 'to', type: 'string', description: "Recipient's email address", required: true },
      { name: 'subject', type: 'string', description: 'Email subject line', required: true },
      { name: 'body', type: 'string', description: 'Email body content', required: true },
    ],
  },
  {
    key: 'create_lead',
    icon: 'i-lucide-user-plus',
    titleKey: 'AI_AGENT_SETTINGS.PRESETS.CREATE_LEAD.TITLE',
    descriptionKey: 'AI_AGENT_SETTINGS.PRESETS.CREATE_LEAD.DESCRIPTION',
    toolDescription:
      'Capture a sales lead. Collect the name, contact details, and what they need before calling this - ask follow-up questions rather than guessing.',
    paramSchema: [
      { name: 'name', type: 'string', description: "Customer's name", required: true },
      { name: 'contact', type: 'string', description: 'Best email or phone number to reach them', required: true },
      { name: 'need', type: 'string', description: 'What they are looking for', required: true },
      { name: 'budget', type: 'string', description: 'Budget, if mentioned', required: false },
      { name: 'timeline', type: 'string', description: 'When they need this by, if mentioned', required: false },
    ],
  },
  {
    key: 'book_appointment',
    icon: 'i-lucide-calendar-check',
    titleKey: 'AI_AGENT_SETTINGS.PRESETS.BOOK_APPOINTMENT.TITLE',
    descriptionKey: 'AI_AGENT_SETTINGS.PRESETS.BOOK_APPOINTMENT.DESCRIPTION',
    toolDescription:
      'Book an appointment. Collect the customer\'s preferred date, time, and reason for the visit before calling this - confirm the booking back to the customer once it succeeds.',
    paramSchema: [
      { name: 'preferred_date', type: 'string', description: 'Preferred date for the appointment', required: true },
      { name: 'preferred_time', type: 'string', description: 'Preferred time for the appointment', required: true },
      { name: 'reason', type: 'string', description: 'Reason for the appointment', required: false },
    ],
  },
  {
    key: 'create_order',
    icon: 'i-lucide-shopping-cart',
    titleKey: 'AI_AGENT_SETTINGS.PRESETS.CREATE_ORDER.TITLE',
    descriptionKey: 'AI_AGENT_SETTINGS.PRESETS.CREATE_ORDER.DESCRIPTION',
    toolDescription:
      'Create an order or service request. Collect exactly what they want, the quantity, and any relevant details before calling this.',
    paramSchema: [
      { name: 'item', type: 'string', description: 'What the customer wants to order', required: true },
      { name: 'quantity', type: 'string', description: 'How many/how much', required: true },
      { name: 'notes', type: 'string', description: 'Any other relevant details', required: false },
    ],
  },
];

export const findPreset = key => ACTION_PRESETS.find(p => p.key === key);
