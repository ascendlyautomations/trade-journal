-- Confirmed privacy holes:
-- 1. Legacy permissive INSERT policies on room_members ("Users can join rooms",
--    "Users can rejoin rooms") are OR'd with room_members_insert_self, so any
--    authenticated user can join an approval-only room.
-- 2. The approval branch compared the join-request room id to itself, because
--    an unqualified room_id bound to the subquery. One approved request anywhere
--    then passed the check for every room.
-- 3. Clearing left_at reactivated membership without join_policy or approval.
-- 4. followers DELETE only allowed follower_id = auth.uid(), so "remove follower"
--    deleted zero rows and private-profile access remained.

drop policy if exists "Users can join rooms" on public.room_members;
drop policy if exists "Users can rejoin rooms" on public.room_members;

drop policy if exists "room_members_insert_self" on public.room_members;
create policy "room_members_insert_self"
  on public.room_members
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and left_at is null
    and exists (
      select 1
      from public.rooms r
      where r.id = room_members.room_id
    )
    and not public.is_room_banned(room_members.room_id, auth.uid())
    and not exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and coalesce(p.is_banned, false)
    )
    and (
      public.is_room_owner(room_members.room_id, auth.uid())
      or exists (
        select 1
        from public.rooms r
        where r.id = room_members.room_id
          and coalesce(r.join_policy, 'open') = 'open'
      )
      or exists (
        select 1
        from public.room_join_requests jr
        where jr.room_id = room_members.room_id
          and jr.user_id = auth.uid()
          and jr.status = 'approved'
      )
    )
  );

create or replace function public.room_members_before_update_guard()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if old.room_id is distinct from new.room_id
     or old.user_id is distinct from new.user_id
  then
    raise exception 'room_id and user_id are immutable on room_members';
  end if;

  if old.left_at is not null and new.left_at is null then
    if public.is_room_banned(new.room_id, new.user_id) then
      raise exception 'banned from this room';
    end if;

    if not (
      public.is_room_owner(new.room_id, new.user_id)
      or exists (
        select 1
        from public.rooms r
        where r.id = new.room_id
          and coalesce(r.join_policy, 'open') = 'open'
      )
      or exists (
        select 1
        from public.room_join_requests jr
        where jr.room_id = new.room_id
          and jr.user_id = new.user_id
          and jr.status = 'approved'
      )
    ) then
      raise exception 'room_join_not_allowed' using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop policy if exists "followers_delete_by_followee" on public.followers;
create policy "followers_delete_by_followee"
  on public.followers
  for delete
  to authenticated
  using (following_id = auth.uid());

comment on policy "followers_delete_by_followee" on public.followers is
  'The followed profile may remove a follower. Access checks read followers live, so this revoke is immediate.';
