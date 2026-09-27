-- Author's note: a silent steering note set with /note, injected as the last block of the
-- system prompt every turn. Lives on the session, so a new session starts without one.
alter table public.sessions
  add column if not exists note text;
