# Telegram Roleplay Bot

A personal Telegram chatbot with a persistent persona and conversation memory, in the spirit of SillyTavern character cards. Inference and embeddings run locally.

```
Telegram → n8n workflow → oMLX (local LLM) → Telegram
                 ↕              ↕
    Postgres + pgvector    Ollama (embeddings)
       (Supabase)
```

## Components

| Part | Where |
|---|---|
| Bot logic | n8n workflow **"Lars 2, Telegram bot"** (live). The original OpenRouter version, **"Lars, Telegram bot"**, is unpublished. |
| LLM | oMLX on Hephaestus (Mac Studio, M4 Max 64 GB), OpenAI-compatible `/v1/chat/completions`, bearer-token auth |
| Model | `Cydonia-24B-v4.3-heretic-mlx-4bit` (Mistral Small 3.2 24B RP finetune, Mistral v7 Tekken template) |
| Embeddings | `nomic-embed-text` (768d) on Ollama, also on Hephaestus |
| Memory | `public.messages` on Supabase Postgres: recent window per chat + character, plus pgvector semantic recall of older exchanges |
| Schema | [`supabase/migrations/`](supabase/migrations/) — applied with `supabase db push` (repo is linked to the project) |
| Maintenance | n8n workflow **"Lars memory backfill"** — embeds any exchange saved without an embedding |
| `chat.py` | Throwaway Python PoC (long-polling). Superseded by the n8n workflow. |

## Commands

| Command | Effect |
|---|---|
| `/new`, `/clear`, `/start` | Start a fresh conversation. Old messages are archived: out of the recent window, still searchable by recall |
| `/swipe` | Regenerate the last reply (SillyTavern-style re-roll). The new exchange replaces the old one once it's saved |
| `/reset` | Permanently delete all history with this character |

BotFather `/setcommands`:
```
new - Start a fresh conversation (Lars still remembers past chats)
clear - Same as /new
swipe - Regenerate Lars's last reply
reset - Permanently delete all history with Lars
```

## n8n workflow

1. **Intake** — Telegram trigger (allowlisted chat ID) → **Character Card** → **Route Command** (commands vs chat)
2. **Reset** — `/reset` hard-deletes; `/clear` / `/new` / `/start` set `archived_at`
3. **Swipe** — find the last exchange; if there is one, re-run its user message through the chat turn with a cutoff so the old exchange is excluded from context
4. **Chat turn**
   - **Turn Input** — the message to answer (new text, or the swiped one) and the swipe cutoff
   - Typing indicator → embed the message → fetch recent window + top-K similar older exchanges → **Build Messages** (system prompt + recalled moments + history + message)
   - **Call oMLX** → **Clean Reply** (strips any `<think>…</think>` reasoning) → **Format Reply** (Markdown → Telegram HTML, everything else escaped) → **Send Reply**
   - If Telegram rejects the HTML, **Send Plain Reply** resends it fully escaped (≤ 4000 chars)
   - In parallel: embed the exchange → **Save Turn** (on `/swipe`, deletes the old exchange in the same statement)
5. LLM, Postgres and delivery errors are sent to the chat as `[error: …]`. Nothing is saved if the LLM call fails; a failed delivery doesn't block saving.
6. If Ollama is unreachable, recall is skipped and turns are saved without embeddings; run **Lars memory backfill** afterwards.

### Character Card

Everything tunable lives in one Set node. Edit, then **publish** — saving only creates a draft on a published workflow.

| Field | Current | Notes |
|---|---|---|
| `name` | Lars | Also the memory key: a new name starts a separate history |
| `system_prompt` | — | Written as an ongoing conversation ("never re-introduce yourself"), with style rules |
| `model` | `Cydonia-24B-v4.3-heretic-mlx-4bit` | Must match the oMLX model ID exactly |
| `temperature` / `top_p` / `min_p` | 0.7 / 0.92 / 0.03 | Quant author's tested settings |
| `repetition_penalty` / `repetition_context_size` | 1.08 / 256 | MLX's default context for the penalty is only ~20 tokens |
| `frequency_penalty` | 0 | Off, to avoid stacking with the repetition penalty |
| `xtc_threshold` / `xtc_probability` | 0.1 / 0 | XTC off; set probability 0.5 to try it |
| `max_tokens` | 2000 | |
| `context_window_limit` | 20 | Recent messages sent every turn |
| `memory_top_k` / `memory_min_similarity` | 5 / 0.6 | Recalled exchanges and cosine threshold |

oMLX's accepted request parameters are listed in its OpenAPI schema at `http://<host>:5678/openapi.json`. Thinking/reasoning is not enabled.

### Context size

The prompt is bounded regardless of conversation length: system prompt + ≤ 20 messages + ≤ 5 recalled exchanges. Typical prompts are 2–8k tokens (well under 2 GB of KV cache for a 24B model), so a long conversation can't exhaust memory on its own.

### Credentials

- **Telegram** — bot token
- **oMLX API key** — HTTP bearer token
- **Postgres** — Supabase connection (use the *session pooler* host, port 5432, SSL on; enable *Ignore SSL Issues* or trust Supabase's CA via `NODE_EXTRA_CA_CERTS`)

The Ollama and oMLX URLs are hardcoded in the HTTP Request nodes (LAN IP of Hephaestus).

> Only one consumer per bot token: activating the n8n trigger registers a webhook, which disables `getUpdates` polling in `chat.py`.

## Data and privacy

| Service | Sees |
|---|---|
| oMLX, Ollama | Local only |
| Supabase | Full transcript and embeddings (RLS blocks the public API, not Supabase itself) |
| Telegram | All messages — bot chats are cloud chats, not end-to-end encrypted |

Options for going further: move Postgres to the homelab (schema is portable, needs pgvector), and replace Telegram with Signal via `signal-cli-rest-api` (needs a dedicated number for the bot, e.g. a prepaid SIM) or an n8n chat page over Tailscale.

## Schema

```sql
messages (id, chat_id, character, role, content, embedding vector(768), archived_at, created_at)
```

`embedding` is set only on assistant rows and embeds the whole exchange (preceding user message + reply). `archived_at` is set by `/clear` / `/new`: archived rows leave the recent window but remain recallable.

Add schema changes as new timestamped files in `supabase/migrations/`; never edit an applied migration.

## Roadmap

- [x] Telegram → LLM → Telegram
- [x] Postgres sliding-window memory
- [x] Character card (Set node in the workflow)
- [x] `/clear` / `/new` (archive) and `/reset` (delete)
- [x] Semantic recall with pgvector + `nomic-embed-text`
- [x] Local inference on oMLX, sampler settings in the character card
- [x] Markdown → Telegram HTML with plain-text fallback; `<think>` stripping
- [x] `/swipe` to regenerate the last reply
- [ ] Self-hosted Postgres
- [ ] End-to-end encrypted transport (Signal)
