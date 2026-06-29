-- Reels: first-class vertical video content on user profiles.

create table if not exists public.reels (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  caption text,
  video_url text not null,
  thumbnail_url text not null,
  duration_seconds integer,
  visibility text not null default 'public'
    check (visibility in ('public', 'private')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists reels_user_id_created_at_idx
  on public.reels (user_id, created_at desc);

create index if not exists reels_created_at_idx
  on public.reels (created_at desc);

comment on table public.reels is
  'User-published vertical videos; profile-scoped in phase 1.';
comment on column public.reels.visibility is
  'Per-reel visibility; profile privacy RLS still applies for private profiles.';

create or replace function public.set_reels_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists reels_set_updated_at on public.reels;

create trigger reels_set_updated_at
  before update on public.reels
  for each row
  execute function public.set_reels_updated_at();

alter table public.reels enable row level security;

drop policy if exists reels_select_visible on public.reels;
drop policy if exists reels_insert_own on public.reels;
drop policy if exists reels_update_own on public.reels;
drop policy if exists reels_delete_own on public.reels;

create policy reels_select_visible
  on public.reels
  for select
  to anon, authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.profiles p
      where p.id = reels.user_id
        and coalesce(p.is_private, false) = false
    )
    or (
      auth.uid() is not null
      and exists (
        select 1
        from public.followers f
        where f.following_id = reels.user_id
          and f.follower_id = auth.uid()
      )
    )
  );

create policy reels_insert_own
  on public.reels
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy reels_update_own
  on public.reels
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy reels_delete_own
  on public.reels
  for delete
  to authenticated
  using (user_id = auth.uid());

grant select on table public.reels to anon, authenticated;
grant insert, update, delete on table public.reels to authenticated;

-- =============================================================================
-- Storage bucket: reels (videos + thumbnails)
-- =============================================================================

insert into storage.buckets (id, name, public)
values ('reels', 'reels', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists reels_storage_select on storage.objects;
drop policy if exists reels_storage_insert on storage.objects;
drop policy if exists reels_storage_update_own on storage.objects;
drop policy if exists reels_storage_delete_own on storage.objects;

create policy reels_storage_select
  on storage.objects
  for select
  using (bucket_id = 'reels');

create policy reels_storage_insert
  on storage.objects
  for insert
  with check (
    bucket_id = 'reels'
    and auth.role() = 'authenticated'
  );

create policy reels_storage_update_own
  on storage.objects
  for update
  using (
    bucket_id = 'reels'
    and auth.uid()::text = (storage.foldername (name))[1]
  );

create policy reels_storage_delete_own
  on storage.objects
  for delete
  using (
    bucket_id = 'reels'
    and auth.uid()::text = (storage.foldername (name))[1]
  );
