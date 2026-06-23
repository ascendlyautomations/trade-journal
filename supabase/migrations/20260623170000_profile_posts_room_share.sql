-- Room share cards in profile / feed posts.
alter table public.profile_posts
  add column if not exists room_id uuid references public.rooms (id) on delete set null,
  add column if not exists room_name text,
  add column if not exists room_logo text,
  add column if not exists room_description text;

create index if not exists profile_posts_room_id_idx
  on public.profile_posts (room_id)
  where room_id is not null;

comment on column public.profile_posts.room_id is
  'When set, post renders as a trade room share card in the feed.';
comment on column public.profile_posts.room_name is
  'Snapshot of room name at post time.';
comment on column public.profile_posts.room_logo is
  'Snapshot of room image URL at post time.';
comment on column public.profile_posts.room_description is
  'Snapshot of room description at post time.';
