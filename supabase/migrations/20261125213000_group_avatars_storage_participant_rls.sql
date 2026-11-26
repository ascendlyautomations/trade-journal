-- Group chat avatars: public read, participant-only write on conversation-scoped paths.
-- RESTRICTIVE policies cap legacy permissive storage policies for this bucket only.
-- Path shape matches web + native: `{conversation_id}/opt/{timestamp}.jpg`.

insert into storage.buckets (id, name, public)
values ('group-avatars', 'group-avatars', true)
on conflict (id) do update set public = excluded.public;

create or replace function public.group_avatar_storage_object_allowed(p_object_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with parts as (
    select (storage.foldername(p_object_name))[1] as head
  )
  select exists (
    select 1
    from parts p
    join public.conversations c on c.id::text = p.head
    where p.head ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and c.is_group is true
      and public.is_conversation_participant(c.id, auth.uid())
  );
$$;

comment on function public.group_avatar_storage_object_allowed(text) is
  'True when the storage object path is under a group conversation id and the caller is a participant.';

drop policy if exists group_avatars_storage_select on storage.objects;
create policy group_avatars_storage_select
  on storage.objects
  for select
  to authenticated, anon
  using (bucket_id = 'group-avatars');

drop policy if exists group_avatars_storage_insert_participant on storage.objects;
drop policy if exists group_avatars_storage_insert_restrict on storage.objects;
create policy group_avatars_storage_insert_restrict
  on storage.objects
  as restrictive
  for insert
  to authenticated
  with check (
    bucket_id is distinct from 'group-avatars'
    or (
      not public.guest_session_is_read_only()
      and public.group_avatar_storage_object_allowed(name)
    )
  );

drop policy if exists group_avatars_storage_update_participant on storage.objects;
drop policy if exists group_avatars_storage_update_restrict on storage.objects;
create policy group_avatars_storage_update_restrict
  on storage.objects
  as restrictive
  for update
  to authenticated
  using (
    bucket_id is distinct from 'group-avatars'
    or (
      not public.guest_session_is_read_only()
      and public.group_avatar_storage_object_allowed(name)
    )
  )
  with check (
    bucket_id is distinct from 'group-avatars'
    or (
      not public.guest_session_is_read_only()
      and public.group_avatar_storage_object_allowed(name)
    )
  );

drop policy if exists group_avatars_storage_delete_participant on storage.objects;
drop policy if exists group_avatars_storage_delete_restrict on storage.objects;
create policy group_avatars_storage_delete_restrict
  on storage.objects
  as restrictive
  for delete
  to authenticated
  using (
    bucket_id is distinct from 'group-avatars'
    or (
      not public.guest_session_is_read_only()
      and public.group_avatar_storage_object_allowed(name)
    )
  );