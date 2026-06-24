-- DM shares for profile wall posts (distinct from trade feed posts in messages.post_id).

alter table public.messages
  add column if not exists profile_post_id uuid references public.profile_posts (id) on delete cascade;

create index if not exists messages_profile_post_id_idx
  on public.messages (profile_post_id)
  where profile_post_id is not null;
