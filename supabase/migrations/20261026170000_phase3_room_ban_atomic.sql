-- Phase 3: atomic room ban + soft-remove (Web/iOS parity).

create or replace function public.rpc_v1_ban_trade_room_member(
  p_room_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if p_user_id = v_actor then
    raise exception 'cannot ban self' using errcode = '42501';
  end if;

  if not public.can_moderate_room_member_target(p_room_id, v_actor, p_user_id) then
    raise exception 'permission denied' using errcode = '42501';
  end if;

  insert into public.room_bans (room_id, user_id, banned_by)
  values (p_room_id, p_user_id, v_actor)
  on conflict (room_id, user_id) do nothing;

  update public.room_members
  set left_at = timezone('utc', now())
  where room_id = p_room_id
    and user_id = p_user_id
    and left_at is null;
end;
$$;

comment on function public.rpc_v1_ban_trade_room_member(uuid, uuid) is
  'Moderator/owner ban: room_bans row + soft-remove active membership in one transaction.';

revoke all on function public.rpc_v1_ban_trade_room_member(uuid, uuid) from public;
grant execute on function public.rpc_v1_ban_trade_room_member(uuid, uuid) to authenticated;
