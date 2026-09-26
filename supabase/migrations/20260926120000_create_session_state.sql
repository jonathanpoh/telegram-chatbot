-- Rolling story state: one LLM-written summary per active conversation, rewritten every
-- N turns from the previous summary plus the messages since through_id. /clear and /reset delete it.
create table if not exists public.session_state (
  chat_id     bigint not null,
  character   text not null,
  summary     text not null,
  through_id  bigint not null,  -- last messages.id folded into the summary
  updated_at  timestamptz not null default now(),
  primary key (chat_id, character)
);

-- Same as messages: RLS with no policies blocks the REST API; n8n connects as postgres.
alter table public.session_state enable row level security;
