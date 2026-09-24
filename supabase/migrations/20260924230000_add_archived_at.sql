-- /reset archives instead of deleting: archived rows drop out of the recent window
-- but stay searchable by semantic recall. /forget still hard-deletes.
alter table public.messages
  add column if not exists archived_at timestamptz;
