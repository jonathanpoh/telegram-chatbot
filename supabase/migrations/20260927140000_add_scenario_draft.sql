-- /newscenarios: LLM-written scenario ideas are stored as drafts (enabled = false, draft = true)
-- so the picker and /scene ignore them; /keep_<id> promotes one to a normal enabled scenario.
-- The next /newscenarios deletes any drafts that weren't kept.
alter table public.scenarios
  add column if not exists draft boolean not null default false;
