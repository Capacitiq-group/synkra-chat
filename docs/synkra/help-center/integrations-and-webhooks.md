# Integrations and webhooks

## What integrations are available?

Settings → Integrations lists what's available to connect — this
varies and expands over time, so check there for the current list
rather than relying on a fixed list here.

## What's a webhook?

A webhook sends Chat event data (a new conversation, a new message,
and similar events) to a URL you specify, in real time, so an external
system of yours can react to what's happening in Chat. Set these up
under Settings → Integrations → Webhooks.

## What's the difference between a webhook and a custom tool used by the AI Agent?

A webhook is a one-way notification you configure to react to Chat
events elsewhere. Custom tools the AI Agent can call during a
conversation to take an action are a related but currently unavailable
capability — see [Synkra AI Agent](./ai-agent.md).

## Who can manage integrations and webhooks?

Creating, editing, and deleting webhooks is administrator-only.

## Can I see what data a webhook sends?

Yes, when creating one you can select the specific events you want it
to fire on, and the payload follows a consistent structure per event
type.
