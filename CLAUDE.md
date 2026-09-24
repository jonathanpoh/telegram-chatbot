# Telegram Roleplay Bot — Project Brief

## Overview

A personal Telegram bot backed by n8n, OpenRouter, and persistent conversation memory. Sole user. Inspired by SillyTavern's character card system — define a persona, pick a model, have persistent context-aware conversations.

## Architecture

```
Telegram (trigger) → n8n workflow → OpenRouter API → Telegram (reply)
```

- **Telegram**: native n8n Telegram trigger + send message nodes
- **OpenRouter**: via n8n's HTTP Request node using the OpenAI-compatible endpoint (`https://openrouter.ai/api/v1`). Direct HTTP gives full control over the messages array — important for roleplay prompt formatting.
- **Memory**: PostgreSQL (simple sliding window for v1)
- **Character card**: single character to start; separate bots per character rather than in-chat switching

## Implementation Approach

Use **manual HTTP Request nodes** (not the n8n AI Agent node) to build the messages array explicitly in a Code node. This gives full control over system prompt placement and message structure — the AI Agent abstraction is too limiting for roleplay use cases.

## Memory — v1

Simple **sliding window** via PostgreSQL:

- Store each message with `chat_id`, `role` (`user`|`assistant`), `content`, `timestamp`
- On each turn: fetch last N messages for the `chat_id`, prepend system prompt, append new user message, POST to OpenRouter, store both the user message and assistant reply
- Survives workflow restarts, easy to inspect and edit directly in the DB

## Memory — v2 (future)

Add **pgvector** to the existing Postgres instance (`CREATE EXTENSION vector;`) for semantic recall:

- Embed each message with a consistent embedding model (Ollama + `nomic-embed-text` preferred — local, free, solid quality)
- On each turn: embed incoming message → similarity search → retrieve top-K semantically relevant past exchanges
- Hybrid context: character card / system prompt → relevant memories (vector) → recent window (last 6–10 messages) → current user message

Schema sketch:
```sql
CREATE EXTENSION vector;

CREATE TABLE messages (
  id          SERIAL PRIMARY KEY,
  character   TEXT,
  role        TEXT,
  content     TEXT,
  embedding   vector(768),  -- match embedding model dimensions
  created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX ON messages USING ivfflat (embedding vector_cosine_ops);
```

## Character Card

Stored as JSON (file or DB row). Fields:
- `name`
- `system_prompt`
- `model` (OpenRouter model string, e.g. `anthropic/claude-3.5-sonnet`)
- `temperature`
- `context_window_limit` (max messages to include)

Injected as the first `role: system` message in every request.

## Suggested Build Order

1. Telegram trigger → static system prompt + OpenRouter HTTP call → reply *(no memory, just prove the pipe works)*
2. Add PostgreSQL sliding window memory (store/retrieve by `chat_id`)
3. Load character card from JSON/DB
4. Add `/reset` command to clear conversation history
5. *(Later)* Enable pgvector extension and add semantic recall layer
