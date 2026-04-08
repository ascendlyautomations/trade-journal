-- Wall posts for profiles (separate from trade "posts").
create table if not exists public.profile_posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  content text,
  image_url text,
  created_at timestamptz not null default now()
);

create index if not exists profile_posts_user_id_created_at_idx
  on public.profile_posts (user_id, created_at desc);

alter table public.profile_posts enable row level security;

create policy "profile_posts_select_all"
  on public.profile_posts
  for select
  using (true);

create policy "profile_posts_insert_own"
  on public.profile_posts
  for insert
  with check (auth.uid() = user_id);

create policy "profile_posts_update_own"
  on public.profile_posts
  for update
  using (auth.uid() = user_id);

create policy "profile_posts_delete_own"
  on public.profile_posts
  for delete
  using (auth.uid() = user_id);

-- Public bucket for profile post images.
insert into storage.buckets (id, name, public)
values ('profile_posts', 'profile_posts', true)
on conflict (id) do update set public = excluded.public;

create policy "profile_posts_storage_select"
  on storage.objects
  for select
  using (bucket_id = 'profile_posts');

create policy "profile_posts_storage_insert"
  on storage.objects
  for insert
  with check (
    bucket_id = 'profile_posts'
    and auth.role() = 'authenticated'
  );

create policy "profile_posts_storage_update_own"
  on storage.objects
  for update
  using (
    bucket_id = 'profile_posts'
    and auth.uid()::text = (storage.foldername (name))[1]
  );

create policy "profile_posts_storage_delete_own"
  on storage.objects
  for delete
  using (
    bucket_id = 'profile_posts'
    and auth.uid()::text = (storage.foldername (name))[1]
  );

comment on table public.profile_posts is
  'User-authored wall posts on profile pages; not tied to trades.';
