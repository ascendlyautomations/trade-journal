-- Voice messages for DMs and Trade Rooms — audio stored in Supabase Storage, referenced by URL.

alter table public.messages
  add column if not exists audio_url text,
  add column if not exists audio_duration_ms integer;

alter table public.room_messages
  add column if not exists audio_url text,
  add column if not exists audio_duration_ms integer;

comment on column public.messages.audio_url is
  'Public HTTPS URL for a voice message attachment (AAC/m4a in message-audio bucket).';
comment on column public.messages.audio_duration_ms is
  'Recorded voice message duration in milliseconds for inbox/thread UI.';
comment on column public.room_messages.audio_url is
  'Public HTTPS URL for a voice message attachment (AAC/m4a in message-audio bucket).';
comment on column public.room_messages.audio_duration_ms is
  'Recorded voice message duration in milliseconds for inbox/thread UI.';

-- Dedicated voice bucket — public read, authenticated write scoped to caller folder.
insert into storage.buckets (id, name, public)
values ('message-audio', 'message-audio', true)
on conflict (id) do nothing;

drop policy if exists "message_audio_storage_insert_own" on storage.objects;
create policy "message_audio_storage_insert_own"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'message-audio'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "message_audio_storage_update_own" on storage.objects;
create policy "message_audio_storage_update_own"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'message-audio'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- Thread bootstrap rows include voice metadata.
create or replace function public.rpc_v1_conversation_thread_message_row(p_message_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'id', m.id,
    'conversation_id', m.conversation_id,
    'sender_id', m.sender_id,
    'sender_anonymized', coalesce(m.sender_anonymized, false),
    'content', m.content,
    'created_at', case
      when m.created_at is null then null
      else to_char(timezone('utc', m.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    end,
    'seen_by', coalesce(m.seen_by, '{}'::uuid[]),
    'type', m.type,
    'trade_id', m.trade_id,
    'post_id', m.post_id,
    'profile_post_id', m.profile_post_id,
    'achievement_post_id', m.achievement_post_id,
    'reel_id', m.reel_id,
    'parent_message_id', m.parent_message_id,
    'deleted_for_everyone', coalesce(m.deleted_for_everyone, false),
    'image_url', m.image_url,
    'audio_url', m.audio_url,
    'audio_duration_ms', m.audio_duration_ms,
    'is_system', coalesce(m.is_system, false),
    'profiles', case
      when m.sender_id is null then null
      else (
        select jsonb_build_object(
          'username', pr.username,
          'avatar_url', pr.avatar_url
        )
        from public.profiles pr
        where pr.id = m.sender_id
      )
    end
  )
  from public.messages m
  where m.id = p_message_id;
$$;

revoke all on function public.rpc_v1_conversation_thread_message_row(uuid) from public;
grant execute on function public.rpc_v1_conversation_thread_message_row(uuid) to authenticated;

-- Inbox preview recognizes voice rows.
create or replace function public._v2_messaging_inbox_preview_text(
  p_deleted_for_everyone boolean,
  p_is_system boolean,
  p_type text,
  p_content text,
  p_image_url text,
  p_trade_id uuid
)
returns text
language sql
immutable
security invoker
set search_path = public, pg_temp
as $$
  select case
    when coalesce(p_deleted_for_everyone, false) then 'Message deleted'
    when coalesce(p_is_system, false) then 'System message'
    when lower(coalesce(p_type, '')) = 'trade' or p_trade_id is not null then 'Shared a trade'
    when lower(coalesce(p_type, '')) = 'voice' then 'Voice message'
    when p_image_url is not null and btrim(p_image_url) <> '' then 'Photo'
    when p_content is not null and btrim(p_content) <> '' then btrim(p_content)
    else 'New message'
  end;
$$;
