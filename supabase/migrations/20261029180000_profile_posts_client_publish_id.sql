-- Idempotent profile wall post publishes (iOS upload job id / web publish session).
alter table public.profile_posts
  add column if not exists client_publish_id uuid;

create unique index if not exists profile_posts_user_client_publish_id_key
  on public.profile_posts (user_id, client_publish_id)
  where client_publish_id is not null;

comment on column public.profile_posts.client_publish_id is
  'Client-generated publish idempotency key; duplicate inserts resolve to the existing row.';
