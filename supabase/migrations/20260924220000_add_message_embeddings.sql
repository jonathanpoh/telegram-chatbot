-- Semantic recall: each assistant row carries an embedding of the whole exchange
-- (preceding user message + reply), from nomic-embed-text (768 dims) via Ollama.
-- User rows stay NULL; recall pairs each matched reply with the user message before it.
create extension if not exists vector with schema extensions;

alter table public.messages
  add column if not exists embedding extensions.vector(768);

-- HNSW builds incrementally, so it works from an empty table (unlike ivfflat).
create index if not exists messages_embedding_hnsw_idx
  on public.messages using hnsw (embedding extensions.vector_cosine_ops);
