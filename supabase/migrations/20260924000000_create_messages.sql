-- Sliding-window conversation memory for the Telegram roleplay bots.
-- One row per message; history is scoped by (chat_id, character).
create table if not exists public.messages (
  id          bigserial primary key,
  chat_id     bigint not null,
  character   text not null,
  role        text not null check (role in ('user', 'assistant')),
  content     text not null,
  created_at  timestamptz not null default now()
);

create index if not exists messages_chat_character_id_idx
  on public.messages (chat_id, character, id desc);

-- The public schema is exposed via the Supabase REST API. RLS with no policies
-- blocks anon/authenticated access; n8n connects as postgres/service_role, which bypass RLS.
alter table public.messages enable row level security;
