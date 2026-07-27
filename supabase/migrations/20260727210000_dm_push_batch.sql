-- Per-conversation Direct Message push batch windows.
-- Extends push_batch_windows for DM coalescing (same conversation only).

alter table public.push_batch_windows
  drop constraint if exists push_batch_windows_kind_check;

alter table public.push_batch_windows
  add constraint push_batch_windows_kind_check check (
    batch_kind in ('like', 'follow', 'room_digest', 'dm')
  );

comment on table public.push_batch_windows is
  'Open like/follow/room/dm push batch windows. DM rows live until the conversation is opened; like/follow/room rows are deleted after flush.';

-- Atomically bump the unread DM push count for one recipient + conversation.
-- Avoids duplicate notifications when multiple messages arrive concurrently.
create or replace function public.bump_dm_push_batch(
  p_recipient_user_id uuid,
  p_conversation_id text,
  p_meta jsonb,
  p_window_ends_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result_meta jsonb;
begin
  insert into public.push_batch_windows (
    recipient_user_id,
    batch_kind,
    batch_key,
    window_ends_at,
    meta,
    created_at,
    updated_at
  )
  values (
    p_recipient_user_id,
    'dm',
    p_conversation_id,
    p_window_ends_at,
    coalesce(p_meta, '{}'::jsonb) || jsonb_build_object('count', 1),
    now(),
    now()
  )
  on conflict (recipient_user_id, batch_kind, batch_key)
  do update set
    meta =
      public.push_batch_windows.meta
      || coalesce(p_meta, '{}'::jsonb)
      || jsonb_build_object(
        'count',
        coalesce((public.push_batch_windows.meta->>'count')::int, 0) + 1
      ),
    window_ends_at = excluded.window_ends_at,
    updated_at = now()
  returning meta into result_meta;

  return result_meta;
end;
$$;

revoke all on function public.bump_dm_push_batch(uuid, text, jsonb, timestamptz)
  from public, anon, authenticated;
grant execute on function public.bump_dm_push_batch(uuid, text, jsonb, timestamptz)
  to service_role;
