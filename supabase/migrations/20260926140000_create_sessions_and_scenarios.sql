-- Sessions: /new, /clear and /start end the current session and start another with a
-- scenario picked at random (skipping recently used ones). Scenario rows are content,
-- so they are managed in the table editor, not seeded here.
create table if not exists public.scenarios (
  id          bigserial primary key,
  character   text not null,
  title       text not null,
  premise     text not null,  -- becomes the "Current scenario" block
  opener      text,           -- sent verbatim if set; if null, the LLM writes the opening
  enabled     boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.sessions (
  id           bigserial primary key,
  chat_id      bigint not null,
  character    text not null,
  scenario_id  bigint,          -- no FK: sessions outlive edits/deletes of scenarios
  title        text,
  premise      text,            -- snapshot; null falls back to the Character Card scenario
  summary      text,            -- final session_state summary, copied when the session ends
  started_at   timestamptz not null default now(),
  ended_at     timestamptz
);

create index if not exists sessions_chat_character_id_idx
  on public.sessions (chat_id, character, id desc);

-- No FK either: /reset deletes messages and sessions in one statement.
alter table public.messages
  add column if not exists session_id bigint;

-- Existing active conversations become one session each; archived rows keep a null session.
with s as (
  insert into public.sessions (chat_id, character, title)
  select distinct chat_id, character, 'Before session tracking'
  from public.messages
  where archived_at is null
  returning id, chat_id, character
)
update public.messages m set session_id = s.id
from s
where m.chat_id = s.chat_id and m.character = s.character and m.archived_at is null;

alter table public.scenarios enable row level security;
alter table public.sessions enable row level security;
