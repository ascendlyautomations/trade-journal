-- Atomic, idempotent group leave: remove auth.uid() membership + one system line (transaction).
-- DM leave / delete conversation is unchanged (client deletes own participant row only).

create or replace function public.rpc_v1_leave_group_conversation(p_conversation_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_deleted int;
  v_display text;
  v_content text;
begin
  if v_uid is null then
    raise exception 'Not authenticated'
      using errcode = '28000';
  end if;

  if public.guest_session_is_read_only() then
    raise exception 'Guest sessions cannot leave conversations'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.conversations c
    where c.id = p_conversation_id
      and coalesce(c.is_group, false) is true
  ) then
    raise exception 'Not a group conversation'
      using errcode = 'P0001';
  end if;

  if not public.is_conversation_participant(p_conversation_id, v_uid) then
    return jsonb_build_object('status', 'already_left');
  end if;

  perform pg_advisory_xact_lock(
    hashtext('leave_group:' || p_conversation_id::text || ':' || v_uid::text)
  );

  select coalesce(nullif(trim(p.username), ''), 'Someone')
    into v_display
  from public.profiles p
  where p.id = v_uid;

  if v_display is null then
    v_display := 'Someone';
  end if;

  v_content := v_display || ' left the group';

  delete from public.conversation_participants cp
  where cp.conversation_id = p_conversation_id
    and cp.user_id = v_uid;

  get diagnostics v_deleted = row_count;

  if v_deleted = 0 then
    return jsonb_build_object('status', 'already_left');
  end if;

  insert into public.messages (
    conversation_id,
    content,
    sender_id,
    is_system,
    channel
  )
  values (
    p_conversation_id,
    v_content,
    null,
    true,
    null
  );

  return jsonb_build_object('status', 'left');
end;
$$;

comment on function public.rpc_v1_leave_group_conversation(uuid) is
  'Removes the caller from a group conversation and inserts one leave system message atomically.';

revoke all on function public.rpc_v1_leave_group_conversation(uuid) from public;
grant execute on function public.rpc_v1_leave_group_conversation(uuid) to authenticated;