-- Phase 5B: permanent room bans.
-- Depends on Phase 2: public.is_room_owner(uuid, uuid)
-- Depends on Phase 3: public.is_room_banned(uuid, uuid) on room_members INSERT
-- Does not modify rooms, room_messages, room_members, or room_presence RLS policies.
-- Replaces is_room_banned() body; extends room_members update trigger (not RLS).

-- =============================================================================
-- Table
-- =============================================================================

create table if not exists public.room_bans (
  id uuid primary key default extensions.uuid_generate_v4(),
  room_id uuid not null references public.rooms (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  banned_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (room_id, user_id)
);

create index if not exists room_bans_room_id_idx
  on public.room_bans (room_id);

create index if not exists room_bans_user_id_idx
  on public.room_bans (user_id);

comment on table public.room_bans is
  'Permanent room bans. Owner-managed via Manage Members UI.';

-- =============================================================================
-- Ban gate (security definer — enforcement bypasses room_bans RLS)
-- =============================================================================

create or replace function public.is_room_banned(
  p_room_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.room_bans b
    where b.room_id = p_room_id
      and b.user_id = p_user_id
  );
$$;

comment on function public.is_room_banned(uuid, uuid) is
  'True when p_user_id has a permanent ban on p_room_id. Used by room_members INSERT and rejoin guard.';

-- =============================================================================
-- Block banned users from rejoin (left_at = null) without changing room_members RLS
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

  if old.left_at is not null
     and new.left_at is null
     and public.is_room_banned(new.room_id, new.user_id)
  then
    raise exception 'banned from this room';
  end if;

  return new;
end;
$$;

-- =============================================================================
-- RLS: room_bans
-- Owner: SELECT / INSERT / DELETE
-- Members (incl. banned users): no access — no policies granted
-- Anon: denied — no policies granted
-- =============================================================================

alter table public.room_bans enable row level security;

-- SELECT: room owner only (Manage Members banned list)
drop policy if exists "room_bans_select_owner" on public.room_bans;
create policy "room_bans_select_owner"
  on public.room_bans
  for select
  to authenticated
  using (
    public.is_room_owner(room_id, auth.uid())
  );

-- INSERT: room owner only; cannot ban self
drop policy if exists "room_bans_insert_owner" on public.room_bans;
create policy "room_bans_insert_owner"
  on public.room_bans
  for insert
  to authenticated
  with check (
    public.is_room_owner(room_id, auth.uid())
    and banned_by = auth.uid()
    and user_id <> auth.uid()
  );

-- DELETE: room owner only (unban)
drop policy if exists "room_bans_delete_owner" on public.room_bans;
create policy "room_bans_delete_owner"
  on public.room_bans
  for delete
  to authenticated
  using (
    public.is_room_owner(room_id, auth.uid())
  );

-- No UPDATE policy — bans are permanent until owner deletes the row.
-- No member SELECT policy — non-owners cannot read room_bans directly.

-- =============================================================================
-- ROLLBACK (run manually to revert this migration)
-- =============================================================================
-- drop policy if exists "room_bans_select_owner" on public.room_bans;
-- drop policy if exists "room_bans_insert_owner" on public.room_bans;
-- drop policy if exists "room_bans_delete_owner" on public.room_bans;
--
-- alter table public.room_bans disable row level security;
--
-- drop table if exists public.room_bans;
--
-- create or replace function public.is_room_banned(
--   p_room_id uuid,
--   p_user_id uuid
-- )
-- returns boolean
-- language sql
-- stable
-- security invoker
-- set search_path = public
-- as $$
--   select false;
-- $$;
--
-- comment on function public.is_room_banned(uuid, uuid) is
--   'Placeholder: returns false until public.room_bans exists. Gate room_members INSERT/join when implemented.';
--
-- create or replace function public.room_members_before_update_guard()
-- returns trigger
-- language plpgsql
-- security invoker
-- set search_path = public
-- as $$
-- begin
--   if tg_op <> 'UPDATE' then
--     return new;
--   end if;
--
--   if old.room_id is distinct from new.room_id
--      or old.user_id is distinct from new.user_id
--   then
--     raise exception 'room_id and user_id are immutable on room_members';
--   end if;
--
--   return new;
-- end;
-- $$;
