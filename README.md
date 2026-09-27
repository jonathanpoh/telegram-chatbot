# Telegram Roleplay Bot

A personal Telegram roleplay bot with a persistent character, sessions that each start from a scenario, and memory that carries across sessions, in the spirit of SillyTavern character cards. Inference and embeddings run locally.

```
Telegram → n8n workflow → oMLX (local LLM) → Telegram
                 ↕              ↕
    Postgres + pgvector    Ollama (embeddings)
       (Supabase)
```

## Components

| Part | Where |
|---|---|
| Bot logic | n8n workflow **"Lars RP Bot with Scenarios"** (live). Earlier versions, **"Lars 2, Telegram bot"** (chat confidant, oMLX) and **"Lars, Telegram bot"** (OpenRouter), are unpublished. |
| LLM | oMLX on Hephaestus (Mac Studio, M4 Max 64 GB), OpenAI-compatible `/v1/chat/completions`, bearer-token auth |
| Model | `Cydonia-24B-v4.3-heretic-mlx-4bit` (Mistral Small 3.2 24B RP finetune, Mistral v7 Tekken template) |
| Embeddings | `nomic-embed-text` (768d) on Ollama, also on Hephaestus |
| Memory | Supabase Postgres: `messages` (recent window + pgvector recall across all sessions), `session_state` (rolling summary of the current session), `sessions` (one row per session, with its final recap), `scenarios` (session premises and openers) |
| Schema | [`supabase/migrations/`](supabase/migrations/) — applied with `supabase db push` (repo is linked to the project) |
| Maintenance | n8n workflow **"Lars memory backfill"** — embeds any exchange saved without an embedding (session openers are skipped) |
| `chat.py` | Throwaway Python PoC (long-polling). Superseded by the n8n workflow. |

## Commands

| Command | Effect |
|---|---|
| `/new`, `/clear`, `/start` | End the current session with a recap and start a new one from a random scenario; Lars sends the opening message (~20 s). Old messages are archived: out of the recent window, still searchable by recall |
| `/swipe` | Regenerate the last reply (SillyTavern-style re-roll). The new exchange replaces the old one once it's saved. Before you've said anything in a session, it re-rolls the opener instead (same scenario). The old message is edited in place |
| `/note <text>` | Set a silent author's note for this session (tone, pacing, hidden plot beats). Lars follows it every turn without acknowledging it; it's never saved as a message. `/note` alone shows it, `/note clear` removes it. A new session starts without one |
| `/scene` | List the enabled scenarios as tappable `/scene_<id>` commands. Picking one restarts the session on it: if you haven't said anything yet, the current session and its opener are discarded; otherwise it ends with a recap as with `/new`. A scenario used in the last 3 sessions asks for confirmation (`/scene_<id>_yes`) |
| `/reset` | Permanently delete all messages, sessions and summaries with this character, then start a new session |

BotFather `/setcommands`:
```
new - Start a new session (Lars remembers earlier ones)
clear - Same as /new
swipe - Regenerate Lars's last reply
note - Show, set or clear the author's note for this session
scene - Pick the scenario for a new session
reset - Permanently delete all history with Lars
```

## n8n workflow

1. **Intake** — Telegram trigger (allowlisted chat ID) → **Character Card** → **Local Time** (Europe/Lisbon time of day, e.g. `13:15 (afternoon)`; no date, since the story is set in the future) → **Route Command** (session commands, `/swipe`, `/note`, `/scene`, chat)
2. **Session change** (`/new`, `/clear`, `/start`, `/reset`)
   - **Gather Ending Session** → if the user said anything this session (and it isn't `/reset`), **Write Recap**: oMLX turns the rolling notes plus the remaining messages into a past-tense recap (*What happened / Outcomes / Carried forward / Relationship*)
   - **Reset or Clear** — `/reset` deletes messages, sessions and state; otherwise ends the session (stores the recap, falling back to the rolling notes, as `sessions.summary`), archives its messages and clears `session_state`
   - **Start Session** — picks a random enabled scenario for the character, preferring ones not used in the last 3 sessions; with no scenarios, falls back to the Card's `scenario`
   - **Confirm Reset** announces the session → the scenario's fixed `opener` if it has one, otherwise **Write Opener** (oMLX, from the card, previous session's recap, scenario and local time) → **Save Opener** (stored without an embedding) → sent like a normal reply
   - **Scene** — `/scene`: **Scene Lookup** lists the enabled scenarios, or checks the picked one against the last 3 sessions → **Start Scene?** — a new pick (or a confirmed `_yes`) enters the session change path above, with **Start Session** using that scenario and **Reset or Clear** deleting the current session if the user never spoke; otherwise **Scene Reply** sends the list, the repeat confirmation or "not found"
3. **Swipe** — find the last exchange in the current session; if there is one, re-run its user message through the chat turn with a cutoff so the old exchange is excluded from context. If the user hasn't spoken yet, **Find Opener** loads the session's scenario and **Write Opener** writes a new opener; **Save Opener** replaces the old one in the same statement
4. **Note** — `/note`: **Set Note** shows, sets or clears `sessions.note` on the current session → **Confirm Note** replies with a fixed message (no LLM call)
5. **Chat turn**
   - **Turn Input** — the message to answer (new text, or the swiped one) and the swipe cutoff
   - Typing indicator → embed the message → **Fetch Recent History**: recent window, top-K similar older exchanges from any session, the rolling summary, the current scenario and author's note, and the previous session's recap
   - **Build Messages** — system prompt (see below) + history + message. If the window starts with the opener, a synthetic `[Session start]` user turn is prepended (the Mistral template requires user/assistant alternation)
   - **Call oMLX** → **Clean Reply** (strips any `<think>…</think>` reasoning) → **Format Reply** (Markdown → Telegram HTML, everything else escaped) → **Edit or Send?**: on `/swipe`, **Edit Reply** edits the old message in place (if its Telegram ID is known and the edit succeeds); otherwise **Send Reply**
   - If Telegram rejects the HTML, **Send Plain Reply** resends it fully escaped (≤ 4000 chars)
   - In parallel: embed the exchange → **Save Turn** (tagged with the current session and the sent message's Telegram ID; on `/swipe`, deletes the old exchange in the same statement). This branch runs after the sending branch (n8n v1 runs the upper branch first), which is how Save Turn sees the Telegram ID
   - Openers are saved before sending, so **Opener Sent?** → **Save Opener ID** stores their Telegram ID afterwards
6. **Rolling state** — after each saved turn, if ≥ `summary_interval_turns` turns aren't in the summary yet (the latest exchange is excluded so `/swipe` can't leave a replaced reply in it), oMLX merges them into `session_state` (*Events so far / Current situation / Open threads / Mood*)
7. LLM, Postgres and delivery errors are sent to the chat as `[error: …]`. Nothing is saved if the LLM call fails; a failed delivery doesn't block saving. A failed summary or recap is skipped silently.
8. If Ollama is unreachable, recall is skipped and turns are saved without embeddings; run **Lars memory backfill** afterwards.

### System prompt

Assembled in **Build Messages** from the Card fields and the database, in this order (empty blocks are skipped):

1. `rules` — roleplay rules: POV and tense, `*actions*` / `"dialogue"`, never write Jonathan's words or actions, safe word, `((OOC))`
2. `## Lars` — `character`
3. `## Jonathan` — `persona`
4. `## World` — `world`
5. `## Previous session: <title>` — recap of the most recent ended session that has one, framed as over ("not today's agenda")
6. `## Current scenario` — the session's premise (or the Card's `scenario`)
7. `## Current time` — local time of day, for greetings at the start of a session
8. `## Story so far` — rolling summary of this session
9. `## Relevant earlier moments` — recalled exchanges, labelled *earlier this session* or *a previous session*
10. `## Author's note` — the session's `/note`, framed as silent direction; last, so it's closest to the reply

Cydonia's chat template prepends the system prompt to the **latest** user message rather than placing it at the top, so all of this sits right before the model's reply. The template also rejects `system` messages anywhere but first.

### Character Card

Everything tunable lives in one Set node. Edit, then **publish** — saving only creates a draft on a published workflow.

| Field | Current | Notes |
|---|---|---|
| `name` | Lars | Also the memory key: a new name starts a separate history (and uses scenarios with that `character`) |
| `rules` / `character` / `persona_name` / `persona` / `world` | — | Permanent prompt blocks (see *System prompt*) |
| `scenario` | — | Fallback premise when there are no enabled scenarios for the character |
| `model` | `Cydonia-24B-v4.3-heretic-mlx-4bit` | Must match the oMLX model ID exactly |
| `temperature` / `top_p` / `min_p` | 0.7 / 0.92 / 0.03 | Quant author's tested settings |
| `repetition_penalty` / `repetition_context_size` | 1.08 / 256 | MLX's default context for the penalty is only ~20 tokens |
| `frequency_penalty` | 0 | Off, to avoid stacking with the repetition penalty |
| `xtc_threshold` / `xtc_probability` | 0.1 / 0 | XTC off; set probability 0.5 to try it |
| `max_tokens` | 2000 | |
| `context_window_limit` | 20 | Recent messages sent every turn |
| `memory_top_k` / `memory_min_similarity` | 3 / 0.7 | Recalled exchanges and cosine threshold |
| `summary_interval_turns` | 5 | Turns between rolling-summary updates |
| `scenario_no_repeat` | (3) | Not in the Card by default; add a number field to override how many recent scenarios are avoided |

oMLX's accepted request parameters are listed in its OpenAPI schema at `http://<host>:5678/openapi.json`. Thinking/reasoning is not enabled.

### Context size

The prompt is bounded regardless of conversation length: system prompt (with two capped summaries, ≤ ~300 words each) + ≤ 20 messages + ≤ 3 recalled exchanges. Typical prompts are 3–10k tokens (well under 2 GB of KV cache for a 24B model), so a long conversation can't exhaust memory on its own.

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
messages      (id, chat_id, character, role, content, embedding vector(768), session_id, archived_at, telegram_message_id, created_at)
sessions      (id, chat_id, character, scenario_id, title, premise, summary, note, started_at, ended_at)
session_state (chat_id, character, summary, through_id, updated_at)   -- one row: the current session
scenarios     (id, character, title, premise, opener, enabled, created_at)
```

- `messages.embedding` is set only on assistant rows and embeds the whole exchange (preceding user message + reply). Openers have none. Recall, `/swipe` and the backfill pair a reply only with a user message from the **same session**.
- `archived_at` is set when a session ends: archived rows leave the recent window but remain recallable.
- The current session is the latest `sessions` row with `ended_at IS NULL`. `sessions.summary` holds the final recap; `premise` is a snapshot, so editing a scenario doesn't rewrite past sessions.
- **Scenarios** are content, managed in the Supabase table editor, not in migrations. `opener` is optional (null = LLM-written); `enabled = false` takes a scenario out of rotation.

Add schema changes as new timestamped files in `supabase/migrations/`; never edit an applied migration.

## Roadmap

Detailed working notes are in [`TODO.md`](TODO.md).


- [x] Telegram → LLM → Telegram
- [x] Postgres sliding-window memory
- [x] Character card (Set node in the workflow)
- [x] `/clear` / `/new` (archive) and `/reset` (delete)
- [x] Semantic recall with pgvector + `nomic-embed-text`
- [x] Local inference on oMLX, sampler settings in the character card
- [x] Markdown → Telegram HTML with plain-text fallback; `<think>` stripping
- [x] `/swipe` to regenerate the last reply
- [x] Layered prompt (rules / character / persona / world / scenario), local time of day
- [x] Rolling session summary
- [x] Sessions with random scenarios, LLM-written openers and a final recap; recall across sessions
- [x] `/note` author's note
- [ ] LLM-generated scenarios
- [ ] Self-hosted Postgres
- [ ] End-to-end encrypted transport (Signal)
