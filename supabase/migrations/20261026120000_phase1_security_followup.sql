-- Phase 1 follow-up: owner kick vs voluntary leave, ban invalidates join approvals,
-- legacy iOS private invite SELECT (slug capability rows only).

-- =============================================================================
-- 1. Owner/moderator kick marker (not a ban; voluntary leave unchanged)
-- =============================================================================

alter table public.room_members
  add column if not exists owner_removed_at timestamptz;

comment on column public.room_members.owner_removed_at is
  'Set when an owner/moderator soft-removes a member. Blocks self-rejoin until owner re-admits or approves a new join request after this timestamp.';

create or replace function public.room_members_mark_owner_removal()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  -- Soft remove
  if old.left_at is null and new.left_at is not null then
    if new.user_id = auth.uid() then
      return new;
    end if;

    if public.is_room_owner(new.room_id, auth.uid())
       or public.can_moderate_room_member_target(new.room_id, auth.uid(), new.user_id)
    then
      new.owner_removed_at := timezone('utc', now());
    end if;

    return new;
  end if;

  -- Rejoin / re-admit
  if old.left_at is not null and new.left_at is null then
    if new.user_id = auth.uid() then
      if old.owner_removed_at is not null
         and not exists (
           select 1
           from public.room_join_requests jr
           where jr.room_id = new.room_id
             and jr.user_id = new.user_id
             and jr.status = 'approved'
             and jr.resolved_at is not null
             and jr.resolved_at >= old.owner_removed_at
         )
      then
        raise exception 'owner_removed_rejoin_blocked' using errcode = '42501';
      end if;

      new.owner_removed_at := null;
      return new;
    end if;

    if public.is_room_owner(new.room_id, auth.uid())
       or public.can_moderate_room_member_target(new.room_id, auth.uid(), new.user_id)
    then
      new.owner_removed_at := null;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists room_members_mark_owner_removal on public.room_members;
create trigger room_members_mark_owner_removal
  before update on public.room_members
  for each row
  execute function public.room_members_mark_owner_removal();

-- =============================================================================
-- 2. room_members join guard — owner removal + existing private/ban rules
-- =============================================================================

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
          and coalesce(r.is_private, false) = false
          and coalesce(r.join_policy, 'open') = 'open'
          and (
            old.owner_removed_at is null
            or new.user_id is distinct from auth.uid()
          )
      )
      or exists (
        select 1
        from public.room_join_requests jr
        where jr.room_id = new.room_id
          and jr.user_id = new.user_id
          and jr.status = 'approved'
          and (
            old.owner_removed_at is null
            or (
              jr.resolved_at is not null
              and jr.resolved_at >= old.owner_removed_at
            )
          )
      )
      or (
        public.is_room_owner(new.room_id, auth.uid())
        or public.can_moderate_room_member_target(new.room_id, auth.uid(), new.user_id)
      )
    ) then
      raise exception 'room_join_not_allowed' using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

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
    and not exists (
      select 1
      from public.room_members m
      where m.room_id = room_members.room_id
        and m.user_id = auth.uid()
        and m.owner_removed_at is not null
    )
    and (
      public.is_room_owner(room_members.room_id, auth.uid())
      or (
        exists (
          select 1
          from public.rooms r
          where r.id = room_members.room_id
            and coalesce(r.is_private, false) = false
            and coalesce(r.join_policy, 'open') = 'open'
        )
        and not exists (
          select 1
          from public.room_members m
          where m.room_id = room_members.room_id
            and m.user_id = auth.uid()
            and m.owner_removed_at is not null
        )
      )
      or exists (
        select 1
        from public.room_join_requests jr
        where jr.room_id = room_members.room_id
          and jr.user_id = auth.uid()
          and jr.status = 'approved'
          and (
            not exists (
              select 1
              from public.room_members m
              where m.room_id = room_members.room_id
                and m.user_id = auth.uid()
                and m.owner_removed_at is not null
            )
            or exists (
              select 1
              from public.room_members m
              where m.room_id = room_members.room_id
                and m.user_id = auth.uid()
                and m.owner_removed_at is not null
                and jr.resolved_at is not null
                and jr.resolved_at >= m.owner_removed_at
            )
          )
      )
    )
  );

-- =============================================================================
-- 3. Ban → invalidate pending/approved join requests for that member
-- =============================================================================

create or replace function public.room_bans_after_insert_invalidate_join_requests()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.room_join_requests jr
  set status = 'rejected',
      resolved_at = timezone('utc', now()),
      resolved_by = new.banned_by
  where jr.room_id = new.room_id
    and jr.user_id = new.user_id
    and jr.status in ('pending', 'approved');

  return new;
end;
$$;

drop trigger if exists room_bans_invalidate_join_requests on public.room_bans;
create trigger room_bans_invalidate_join_requests
  after insert on public.room_bans
  for each row
  execute function public.room_bans_after_insert_invalidate_join_requests();

-- =============================================================================
-- 4. Legacy iOS: direct rooms SELECT by slug for private invite rows
--    (authenticated only; does not restore profile-wide private listing)
-- =============================================================================

drop policy if exists "rooms_select_invite" on public.rooms;
create policy "rooms_select_invite"
  on public.rooms
  for select
  to authenticated
  using (
    owner_user_id is null
    or (
      slug is not null
      and coalesce(is_private, false) = true
      and coalesce(room_kind, 'community') = 'community'
    )
  );

comment on policy "rooms_select_invite" on public.rooms is
  'Legacy invite deep links (store iOS): read private community rooms by slug. Prefer rpc_v1_trade_room_invite_lookup on new clients; enumerable via slug scan.';
