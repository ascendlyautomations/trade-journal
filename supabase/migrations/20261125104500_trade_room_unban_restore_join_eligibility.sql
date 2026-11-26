-- Unban: lifting room_bans must clear the moderator-removal marker left by the ban
-- soft-remove (rpc_v1_ban_trade_room_member sets left_at → room_members_mark_owner_removal
-- sets owner_removed_at). Without this, room_members_before_update_guard raises
-- room_join_not_allowed after unban even though is_room_banned is false.
--
-- Kicks (no room_bans row) are unchanged. Voluntary leave never sets owner_removed_at.
-- No data backfill: absent a room_bans history/audit table, we cannot distinguish
-- previously unbanned members from ordinary kicks at rest.

create or replace function public.room_bans_after_delete_restore_join_eligibility()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.room_members m
  set owner_removed_at = null
  where m.room_id = old.room_id
    and m.user_id = old.user_id
    and m.left_at is not null
    and m.owner_removed_at is not null;

  return old;
end;
$$;

comment on function public.room_bans_after_delete_restore_join_eligibility() is
  'After unban (DELETE room_bans): clear owner_removed_at on the soft-left membership row so the member may self-rejoin under existing join guards. Does not clear left_at (no auto readmit). Kicks without a ban row are unaffected.';

drop trigger if exists room_bans_restore_join_eligibility on public.room_bans;
create trigger room_bans_restore_join_eligibility
  after delete on public.room_bans
  for each row
  execute function public.room_bans_after_delete_restore_join_eligibility();