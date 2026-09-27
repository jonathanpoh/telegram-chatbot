-- Telegram message ID of a sent assistant reply or opener, so /swipe can edit the message in
-- place instead of sending a new one. Null for user rows and for replies sent before this column.
alter table public.messages
  add column if not exists telegram_message_id bigint;
