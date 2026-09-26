# TODO

Direction: evolve Lars from chat confidant into an RP / interactive-fiction bot. Same world and characters every session, different scenario each time.

## 1. Prompt layers

Split the single `system_prompt` into blocks by how often they change.

Note: Cydonia's chat template (Mistral `[INST]`) doesn't put the system prompt at the top. It prepends it to the **latest** user message, so the whole system prompt already sits at depth 0, where the model pays the most attention. The template also throws on any `system` message outside position 0, and requires strict user/assistant alternation after it.

| Layer | Content | Lifetime |
|---|---|---|
| Rules | RP instructions, POV/tense, formatting, never write for Jonathan, OOC, safe word | Permanent |
| Character | Lars | Permanent |
| Persona | Jonathan | Permanent |
| World | Facility, lab/equipment, volunteer arrangement, how sessions work | Permanent |
| Scenario | Today's focus, setting details, time of day | Per session |
| Opener | Lars's first message | Per session |

- [x] Add Character Card fields (`rules`, `character`, `persona_name`, `persona`, `world`, `scenario`); **Build Messages** assembles them with headings and skips empty blocks (Lars RP Bot with Scenarios, 2026-09-26)
- [x] ~~Move recall out of the system message~~: not needed and not possible, see note above
- [ ] Later: author's note (state is done, see Later). There's no mid-history `system` message, so fold it into the system prompt (already at depth 0), or into the latest user message

## 2. Fix the prompt itself

- [x] Resolve the length conflict: drop "2–3 sentences", pick an RP length (e.g. 1–3 paragraphs)
- [x] Remove confidant/therapist leftovers: "explains in plain language", "gently clarifies misunderstandings", "at most one question", "Thanks for sharing" opener ban
- [x] Replace the adjective pile ("authentic, vivid, varied…") with concrete rules: POV/tense, `*actions*` + "dialogue" formatting (Format Reply already renders `*…*` as italics)
- [x] Hard rule: never write Jonathan's dialogue, actions, thoughts or reactions; describe only what he perceives
- [ ] Flesh out Lars: appearance, speech quirks, what makes him "unorthodox", what he wants from the research
- [ ] Replace "Jonathan is a cis male. Respond appropriately" with a persona block (name, he/him, what Lars knows about him)
- [x] Safe word: define Lars's behaviour on "orange" (stop immediately, end session, check in), not just its existence
- [x] Add OOC convention: `((OOC: …))` = step out of character and answer directly
- [x] Drop "never the same thing twice in a row" from the prompt; enforce it in the scenario picker instead
- [ ] Don't paste the LLM wrapper lines ("Here is a sanitized version…") into the card

## 3. Sessions, recall and openers

- [ ] Add a `session_id` to `messages`; `/new` (and `/clear`, `/start`) starts a new session
- [ ] Decide the cross-session recall policy: bleed across sessions (relationship continuity), restrict to the current session, or recall across sessions but label memories "from a previous session"
- [ ] Openers table: fixed set of scenario + opener pairs; `/new` picks one at random, excluding the last N used
- [ ] Opener vs chat template: history must start with `user` after the system message. An opener stored as the first assistant row will make oMLX error. Options: prepend a synthetic user turn (e.g. `[Session start]`) when the window starts with `assistant`, or put the opener text in the scenario block instead
- [ ] Store the opener as the first assistant row of the session with `embedding = NULL` (or a marker). Otherwise recall pairs it with the previous session's last user message
- [ ] Record which scenario each session used (needed for the "not the last N" exclusion)

## Later

- [x] Rolling state/summary: `session_state` table; every `summary_interval_turns` (default 5) turns after **Save Turn**, oMLX merges the new messages (minus the latest, still-swipeable exchange) into the summary; injected as "Story so far" in the system prompt. `/clear` and `/reset` delete it (2026-09-26)
- [ ] Tune the summary once it has run a few times: interval, 300-word cap, the four labels; consider moving state into the session model when `session_id` lands
- [ ] LLM-generated scenarios: a separate workflow generates scenario + opener ideas into the openers table
- [ ] `/scenario <text>` / `/note <text>` commands to set context from Telegram
- [ ] Lorebook (`context_entries` with keyword or vector triggers, reusing the **Embed Query** vector). Skip until a character actually has lore
