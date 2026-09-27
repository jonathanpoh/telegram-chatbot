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
- [x] Author's note: `/note`, injected as the last system prompt block (there's no mid-history `system` message; the system prompt is already at depth 0) (2026-09-26)

## 2. Fix the prompt itself

- [x] Resolve the length conflict: drop "2–3 sentences", pick an RP length (e.g. 1–3 paragraphs)
- [x] Remove confidant/therapist leftovers: "explains in plain language", "gently clarifies misunderstandings", "at most one question", "Thanks for sharing" opener ban
- [x] Replace the adjective pile ("authentic, vivid, varied…") with concrete rules: POV/tense, `*actions*` + "dialogue" formatting (Format Reply already renders `*…*` as italics)
- [x] Hard rule: never write Jonathan's dialogue, actions, thoughts or reactions; describe only what he perceives
- [x] Flesh out Lars: appearance, speech quirks, what makes him "unorthodox", what he wants from the research
- [x] Replace "Jonathan is a cis male. Respond appropriately" with a persona block (name, he/him, what Lars knows about him)
- [x] Safe word: define Lars's behaviour on "orange" (stop immediately, end session, check in), not just its existence
- [x] Add OOC convention: `((OOC: …))` = step out of character and answer directly
- [x] Drop "never the same thing twice in a row" from the prompt; enforce it in the scenario picker instead

## 3. Sessions, recall and openers

Done 2026-09-26: `sessions` + `scenarios` tables, `messages.session_id`.

- [x] `/new`, `/clear`, `/start` end the current session (copying its `session_state` summary to `sessions.summary`) and start a new one; `/reset` deletes messages, sessions and state
- [x] Cross-session recall: bleeds across sessions; memories are labelled "earlier this session" / "a previous session"
- [x] Previous session's summary injected as `## Previous session: <title>`
- [x] Scenario picker: random enabled scenario for the character, preferring ones not used in the last `scenario_no_repeat` sessions (default 3; add the field to the Character Card to override). No scenarios → falls back to the Card's `scenario`
- [x] Openers: `scenarios.opener` sent verbatim if set; otherwise the LLM writes one from the scenario, previous-session summary and local time
- [x] Opener vs chat template: Build Messages prepends a synthetic `[Session start]` user turn when the window starts with the opener
- [x] Openers saved without an embedding; recall, /swipe and the backfill workflow pair replies with user messages only within the same session
- [x] Write real scenarios in the `scenarios` table (3 neutral starters seeded directly in the DB, not in the repo)
- [x] Final recap on `/new`/`/clear`/`/start`: oMLX writes a past-tense recap (What happened / Outcomes / Carried forward / Relationship) from the rolling notes + remaining messages, stored as `sessions.summary`. Skipped for `/reset` and for sessions where the user never spoke; those are skipped by the "previous session" lookup, which falls back to the last session with notes
- [ ] Longer-term history: only the last session's recap is injected; older sessions reach the prompt only via vector recall. If the relationship arc needs more, add a rolling "history so far" digest updated from each recap
- [ ] Race: a message sent while the opener is still generating (~10 s) doesn't see it, so Lars greets twice. Mitigated with "setting the scene…" + typing indicator; a real fix would make the chat path wait for or skip a pending opener
- [x] `/swipe` re-rolls the opener (same scenario) until the user has spoken; the old opener is replaced on save. The old Telegram message stays in the chat (2026-09-27)
- [x] `/scene` picker: tappable `/scene_<id>` list; restarts the session on the pick (discarding an unused session instead of stacking a new one on it); recent repeats need `/scene_<id>_yes` (2026-09-27)
- [x] Replies capped at ~150 words (rules + Write Opener); recall tightened to top 3 at ≥ 0.7 similarity, since long recalled replies were priming length (2026-09-27)
- [x] `/swipe` edits the old Telegram message in place (`messages.telegram_message_id`); falls back to a new message when the ID is unknown or the edit fails (Lars and Zach, 2026-09-27)
- [x] Add `scene` to BotFather `/setcommands` for both bots (manual). Ported to Zach ERP 2026-09-27

## `/note` (author's note)

Done 2026-09-26: `sessions.note`; **Route Command** → **Set Note** → **Confirm Note**; **Fetch Recent History** returns it, **Build Messages** adds `## Author's note` last.

- Deviation from the agreed design: bare `/note` **shows** the note and `/note clear` (or `off`) clears it, because tapping a command in Telegram's menu sends it bare, which would have silently wiped the note
- Doesn't carry over to the next session, and isn't passed to **Write Opener**, **Summarize State** or **Write Recap**
- [x] Add `note` to BotFather `/setcommands` (manual)
- [x] Try it in a real session: does Cydonia follow it without leaking it into the reply?

## Later

- [x] Rolling state/summary: `session_state` table; every `summary_interval_turns` (default 5) turns after **Save Turn**, oMLX merges the new messages (minus the latest, still-swipeable exchange) into the summary; injected as "Story so far" in the system prompt. `/clear` and `/reset` delete it (2026-09-26)
- [ ] Tune the summary once it has run a few times: interval, 300-word cap, the four labels; consider moving state into the session model when `session_id` lands
- [ ] LLM-generated scenarios: a separate workflow generates scenario + opener ideas into the openers table
- [ ] `/scenario <text>` command to override the current session's premise from Telegram (`/note` is planned above)
- [ ] Lorebook (`context_entries` with keyword or vector triggers, reusing the **Embed Query** vector). Skip until a character actually has lore
