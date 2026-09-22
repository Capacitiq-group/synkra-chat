# Captain AI on the VPS's own Ollama (no per-account keys)

## What's on the server (checked 22 Sep 2026)
Container `ollama` (image `ollama/ollama`), bound to `127.0.0.1:11434` on the
host - only reachable from inside its Docker networks, not from the host's
public IP, which is correct/safe.
Networks it's already on: `bridge`, `coolify`, and staging's own
`tdrusxbd5khg1vyjcd4gdevv` - all with DNS alias `ollama`. **Not yet on**
`0ojl8fw19lens2ifijutg4od` (production).
Models pulled: `qwen2.5:3b-instruct-q4_K_M` (1.9GB), `qwen2.5:7b-instruct-q4_K_M` (4.7GB).

## What changed in code (this branch)
Two real gaps, both now fixed:
1. `Captain::BaseTaskService#build_chat` (the reply-box sparkle icon: rewrite,
   summarize, reply suggestions) called RubyLLM directly with no fallback for
   a model name RubyLLM's own registry doesn't recognise - which is every
   Ollama model. It now retries with `assume_model_exists: true`, the same
   fix a previous session already made for the Captain Assistant chat path
   (`enterprise/app/services/llm/base_ai_service.rb`, 8 Sep commit).
2. Two different places read `CAPTAIN_OPEN_AI_ENDPOINT` and disagreed on
   whether it should include `/v1`. Normalised both to expect a bare host
   (`http://ollama:11434`), matching the majority of existing call sites.

One addition: `CAPTAIN_OPEN_AI_MODEL` used to only override the model for
one narrow feature. It now overrides every Captain feature (the sparkle
icon, label suggestions, FAQ generation, the AI Agent) at once - one knob,
not per-account, as you asked for.

## Setting it up (staging first)
No Docker network change needed for staging - `ollama` is already reachable.

```
docker exec rails-tdrusxbd5khg1vyjcd4gdevv bundle exec rails runner "
  InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT').tap { |c| c.value = 'http://ollama:11434'; c.save! }
  InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY').tap { |c| c.value = 'ollama'; c.save! }
  InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_MODEL').tap { |c| c.value = 'qwen2.5:7b-instruct-q4_K_M'; c.save! }
  GlobalConfig.clear_cache
  puts 'done'
"
```
(Ollama itself doesn't check the API key, but our own code requires one to
be present before it'll try - any non-blank value works.)

For production, first attach the container to its network:
```
docker network connect 0ojl8fw19lens2ifijutg4od ollama
```
then run the same three-line runner against `rails-0ojl8fw19lens2ifijutg4od`.

## Testing
Click the sparkle icon in a conversation's reply box and try Rewrite and
Summarize. Expect a real reply within a few seconds - the container has no
GPU, so a 7B model on CPU is noticeably slower than OpenAI, closer to
5-15 seconds than 1-2.

## What I could not verify
- I have no way to run Ruby or hit the Ollama API from here, so none of
  this has actually executed against a real model yet - the render/config
  logic is right, but the first real test is the one you'll run.
- Whether qwen2.5 handles tool-calling and structured JSON output well
  through Ollama's OpenAI-compatible layer (used by the AI Agent, FAQ
  generation, and label suggestion) is genuinely uncertain with a 3B/7B
  quantized model - test the simple sparkle-icon tasks first, then try the
  AI Agent and FAQ generation separately before trusting them.
- 7B on CPU may be too slow for a live customer-facing AI Agent
  conversation even if it works correctly - that's a judgment call once you
  see the real latency, not something I can predict.
