-- Moderator message delete and unban RLS — prevent acting on elevated members' messages;
-- align unban with can_moderate_room_member_target (same as ban/remove).

drop policy if exists "room_messages_delete_moderator" on public.room_messages;
create policy "room_messages_delete_moderator"
  on public.room_messages
  for delete
  to authenticated
  using (
    public.can_moderate_trade_room(room_id, auth.uid())
    and (
      public.can_manage_trade_room(room_id, auth.uid())
      or (
        not public.is_room_owner(room_id, user_id)
        and not public.has_elevated_room_member_tag(room_id, user_id)
      )
    )
  );

drop policy if exists "room_bans_delete_moderator" on public.room_bans;
create policy "room_bans_delete_moderator"
  on public.room_bans
  for delete
  to authenticated
  using (
    public.can_moderate_room_member_target(room_id, auth.uid(), user_id)
  );