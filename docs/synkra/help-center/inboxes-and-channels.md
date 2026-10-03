# Inboxes and channels

An inbox is where conversations from a specific channel — your website
widget, an email address, WhatsApp, and so on — land. You can have
multiple inboxes, each feeding into the same shared conversation view.

## What channel types are supported?

Website widget (live chat on your site), email, WhatsApp, Facebook,
Instagram, Twitter/X, SMS, Telegram, Line, and a generic API channel
for custom integrations, among others depending on what's enabled on
your account.

## How do I add the website widget to my site?

Settings → Inboxes → Add Inbox → Website. After creating it, you'll
get a small script to paste into your site's HTML — once it's live,
the chat bubble appears and conversations start flowing into that
inbox.

## What's in an inbox's Configuration tab?

For a website widget inbox specifically:

- **Allowed Domains** — restrict which websites the widget is allowed
  to load on. Add your domain(s) here so the widget only ever appears
  where you intend it to — this is enforced at the browser level, not
  just a display setting.
- **Allow Mobile WebView** — turn this on if you're embedding the
  widget inside a mobile app (iOS/Android), since app WebViews don't
  have a normal web domain the way a browser tab does.
- **Identity Validation (Secret Key)** — a secret key used to
  cryptographically verify a logged-in customer's identity when your
  own site initializes the widget with their details. This stops
  anyone from impersonating another customer in the chat widget. You
  can make this mandatory for every identified conversation from the
  toggle below the key.

## How do I customize what the widget looks like?

Settings → Inboxes → your website inbox → Widget Builder — set colors,
the greeting message, and other visual details.

## Can I have a pre-chat form?

Yes — collect a name/email (or custom fields) before a visitor starts
chatting. Configure this under the inbox's Pre-Chat Form tab.

## Who can see a given inbox's conversations?

Whoever is added as a collaborator on that inbox, from the
Collaborators tab in the inbox's settings. Not every teammate
automatically sees every inbox.
