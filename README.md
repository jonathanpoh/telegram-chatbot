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
| Memory | `public.messages` on Supabase Postgres, last N messages per chat + character |
| Schema | [`supabase/migrations/`](supabase/migrations/) — applied by the Supabase GitHub integration |
| `chat.py` | Throwaway Python PoC (long-polling). Superseded by the n8n workflow. |

## n8n workflow

1. **Telegram Message** trigger (restricted to an allowlisted chat ID)
2. **Character Card** — name, system prompt, model, temperature, penalties, context window size
3. **Route Command** — `/reset` or `/start` clears history; any other text is a chat turn
4. **Chat turn** — typing indicator → fetch last N messages → OpenRouter → reply + save both turns
5. OpenRouter errors are sent back to the chat as `[error: …]`; nothing is saved on failure

### Credentials

- **Telegram** — bot token
- **OpenRouter** — API key
- **Postgres** — Supabase connection (use the *session pooler* host, port 5432, SSL on)

> Only one consumer per bot token: activating the n8n trigger registers a webhook, which disables `getUpdates` polling in `chat.py`.

## Schema

```sql
messages (id, chat_id, character, role, content, created_at)
```

Add schema changes as new timestamped files in `supabase/migrations/`; never edit an applied migration.

## Roadmap

- [x] Telegram → OpenRouter → Telegram
- [x] Postgres sliding-window memory
- [x] Character card (Set node in the workflow)
- [x] `/reset`
- [ ] Semantic recall with pgvector + `nomic-embed-text`
