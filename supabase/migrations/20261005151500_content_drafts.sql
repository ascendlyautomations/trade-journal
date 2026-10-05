-- Private composer drafts. These rows are not trades, posts, achievements, or stories.
-- Nothing in feed, profile, analytics, calendar, or social counts should read this table.

create table public.content_drafts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  draft_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint content_drafts_type_check check (
    draft_type in ('trade', 'post', 'achievement', 'story')
  )
);

comment on table public.content_drafts is
  'Private incomplete composer state. Not published content. Owner-only via RLS.';

comment on column public.content_drafts.payload is
  'Composer field snapshot for one draft_type. May reference private draft-media paths, never public content URLs.';

create index content_drafts_user_updated_idx
  on public.content_drafts (user_id, updated_at desc);

alter table public.content_drafts enable row level security;
alter table public.content_drafts force row level security;

revoke all on table public.content_drafts from public, anon;
grant select, insert, update, delete on table public.content_drafts to authenticated;

create policy content_drafts_select_own
  on public.content_drafts
  for select
  to authenticated
  using (user_id = auth.uid());

create policy content_drafts_insert_own
  on public.content_drafts
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and not public.guest_session_is_read_only()
  );

create policy content_drafts_update_own
  on public.content_drafts
  for update
  to authenticated
  using (
    user_id = auth.uid()
    and not public.guest_session_is_read_only()
  )
  with check (
    user_id = auth.uid()
    and not public.guest_session_is_read_only()
  );

create policy content_drafts_delete_own
  on public.content_drafts
  for delete
  to authenticated
  using (
    user_id = auth.uid()
    and not public.guest_session_is_read_only()
  );

-- Private draft attachments. Not a public content bucket.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'draft-media',
  'draft-media',
  false,
  52428800,
  array['image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/quicktime']
)
on conflict (id) do update
set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists draft_media_select_own on storage.objects;
create policy draft_media_select_own
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'draft-media'
    and auth.uid()::text = (storage.foldername(name))[1]
    and not public.guest_session_is_read_only()
  );

drop policy if exists draft_media_insert_own on storage.objects;
create policy draft_media_insert_own
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'draft-media'
    and auth.uid()::text = (storage.foldername(name))[1]
    and not public.guest_session_is_read_only()
  );

drop policy if exists draft_media_update_own on storage.objects;
create policy draft_media_update_own
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'draft-media'
    and auth.uid()::text = (storage.foldername(name))[1]
    and not public.guest_session_is_read_only()
  )
  with check (
    bucket_id = 'draft-media'
    and auth.uid()::text = (storage.foldername(name))[1]
    and not public.guest_session_is_read_only()
  );

drop policy if exists draft_media_delete_own on storage.objects;
create policy draft_media_delete_own
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'draft-media'
    and auth.uid()::text = (storage.foldername(name))[1]
    and not public.guest_session_is_read_only()
  );
