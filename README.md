# Telegram Roleplay Bot

A personal Telegram chatbot with a persistent persona and conversation memory, in the spirit of SillyTavern character cards.

```
Telegram → n8n workflow → OpenRouter → Telegram
                 ↕
        Postgres (Supabase)
```

## Components

| Part | Where |
|---|---|
| Bot logic | n8n workflow **"Lars, Telegram bot"** |
| LLM | OpenRouter chat completions, called via HTTP Request node |
| Memory | `public.messages` on Supabase Postgres: last N messages per chat + character, plus pgvector semantic recall of older exchanges |
| Embeddings | `nomic-embed-text` (768d) on Ollama at Hephaestus |
| Schema | [`supabase/migrations/`](supabase/migrations/) — applied with `supabase db push` (repo is linked to the project) |
| `chat.py` | Throwaway Python PoC (long-polling). Superseded by the n8n workflow. |

## n8n workflow

1. **Telegram Message** trigger (restricted to an allowlisted chat ID)
2. **Character Card** — name, system prompt, model, temperature, penalties, context window size
3. **Route Command** — `/reset` or `/start` clears history; any other text is a chat turn
4. **Chat turn** — typing indicator → embed the message → fetch last N messages + top-K similar older exchanges → build prompt → OpenRouter → reply, then embed the exchange and save both turns
5. OpenRouter and Postgres errors are sent back to the chat as `[error: …]`; nothing is saved if OpenRouter fails
6. If Ollama is unreachable, recall is skipped and turns are saved without embeddings; run the **Lars memory backfill** workflow afterwards to fill them in

Memory tuning lives in the Character Card: `context_window_limit` (recent messages), `memory_top_k` (recalled exchanges), `memory_min_similarity` (cosine threshold, 0–1).

### Credentials

- **Telegram** — bot token
- **OpenRouter** — API key
- **Postgres** — Supabase connection (use the *session pooler* host, port 5432, SSL on)

> Only one consumer per bot token: activating the n8n trigger registers a webhook, which disables `getUpdates` polling in `chat.py`.

## Schema

```sql
messages (id, chat_id, character, role, content, embedding vector(768), created_at)
```

`embedding` is set only on assistant rows and embeds the whole exchange (preceding user message + reply).

Add schema changes as new timestamped files in `supabase/migrations/`; never edit an applied migration.

## Roadmap

- [x] Telegram → OpenRouter → Telegram
- [x] Postgres sliding-window memory
- [x] Character card (Set node in the workflow)
- [x] `/reset`
- [x] Semantic recall with pgvector + `nomic-embed-text`
