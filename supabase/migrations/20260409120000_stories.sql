-- Ephemeral image stories (24h window enforced in app; optional cron to delete old rows).

create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  image_url text not null,
  created_at timestamptz not null default now()
);

create index if not exists stories_user_id_created_at_idx
  on public.stories (user_id, created_at desc);

create index if not exists stories_created_at_idx
  on public.stories (created_at desc);

alter table public.stories enable row level security;

create policy "stories_select_all"
  on public.stories
  for select
  using (true);

create policy "stories_insert_own"
  on public.stories
  for insert
  with check (auth.uid() = user_id);

create policy "stories_update_own"
  on public.stories
  for update
  using (auth.uid() = user_id);

create policy "stories_delete_own"
  on public.stories
  for delete
  using (auth.uid() = user_id);

insert into storage.buckets (id, name, public)
values ('stories', 'stories', true)
on conflict (id) do update set public = excluded.public;

create policy "stories_storage_select"
  on storage.objects
  for select
  using (bucket_id = 'stories');

create policy "stories_storage_insert"
  on storage.objects
  for insert
  with check (
    bucket_id = 'stories'
    and auth.role() = 'authenticated'
  );

create policy "stories_storage_update_own"
  on storage.objects
  for update
  using (
    bucket_id = 'stories'
    and auth.uid()::text = (storage.foldername (name))[1]
  );

create policy "stories_storage_delete_own"
  on storage.objects
  for delete
  using (
    bucket_id = 'stories'
    and auth.uid()::text = (storage.foldername (name))[1]
  );

comment on table public.stories is
  'Short-lived user stories; client filters to last 24 hours.';
