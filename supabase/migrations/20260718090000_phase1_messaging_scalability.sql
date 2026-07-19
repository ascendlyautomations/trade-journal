-- Phase 1 messaging scalability (production-schema-correct):
--   * restore server-enforced DM / room-message abuse limits
--   * replace per-message seen_by history scans with per-member read cursors
--   * add stable keyset-pagination indexes
--
-- Production schema facts this migration targets:
--   * messages.seen_by              = uuid[]
--   * room_messages.seen_by         = jsonb  (array of uuid strings)
--   * conversation_member_preferences has no read-cursor columns yet
--   * room_members has no read-cursor columns yet
--   * room_members primary key is (room_id, user_id) — no surrogate id
--
-- Legacy seen_by columns remain intact. Existing read state is copied into
-- cursors once; RPCs then update/read cursors without rewriting history.

-- ---------------------------------------------------------------------------
-- 0. Notification inserts are server-only
-- ---------------------------------------------------------------------------
-- Authenticated users keep existing RLS select/update/delete. API routes use
-- service_role after resolving recipients from authenticated actions.
revoke insert on table public.notifications from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. Burst + sustained server-side messaging limits
-- ---------------------------------------------------------------------------

insert into public.rate_limit_rules (action, window_seconds, max_count)
values
  ('message_send', 10, 12),
  ('message_send', 300, 90),
  ('message_send', 3600, 500),
  ('room_message', 10, 8),
  ('room_message', 300, 60),
  ('room_message', 3600, 300)
on conflict (action, window_seconds) do update
  set max_count = excluded.max_count;

create or replace function public.rate_limit_messages_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  free_plan_daily_dm_limit constant integer := 25;
  dm_count integer;
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if coalesce(new.is_system, false) then
    return new;
  end if;

  -- Participant/system rows without an explicit sender.
  if new.conversation_id is not null and new.sender_id is null then
    return new;
  end if;

  if new.sender_id is null then
    return new;
  end if;

  -- Abuse limits apply to private conversations and lobby sends.
  perform public.rate_limit_hit('message_send');

  -- Preserve the existing Free plan rolling allowance exactly (conversation DMs only).
  if new.conversation_id is not null
     and not public.profile_is_pro_user(new.sender_id) then
    perform pg_advisory_xact_lock(
      872341,
      hashtext(new.sender_id::text || ':free_plan_dm')
    );
    dm_count := public.free_plan_count_direct_messages_rolling_24h(new.sender_id);
    if coalesce(dm_count, 0) >= free_plan_daily_dm_limit then
      raise exception 'FREE_PLAN_DAILY_DM_LIMIT'
        using hint = 'You''ve reached the Free plan limit of 25 direct messages every 24 hours.';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.rate_limit_messages_before_insert() is
  'Server-side DM abuse limits for all users plus the existing Free plan 25/24h allowance.';

create or replace function public.rate_limit_room_messages_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  perform public.rate_limit_hit('room_message');
  return new;
end;
$$;

comment on function public.rate_limit_room_messages_before_insert() is
  'Server-side Trade Room burst and sustained abuse limits; no plan-based room cap.';

-- ---------------------------------------------------------------------------
-- 2. Read cursor columns (absent in current production schema)
-- ---------------------------------------------------------------------------

alter table public.conversation_member_preferences
  add column if not exists last_read_at timestamptz;

alter table public.conversation_member_preferences
  add column if not exists last_read_message_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'conversation_member_preferences_last_read_message_id_fkey'
  ) then
    alter table public.conversation_member_preferences
      add constraint conversation_member_preferences_last_read_message_id_fkey
      foreign key (last_read_message_id)
      references public.messages (id)
      on delete set null;
  end if;
end $$;

alter table public.room_members
  add column if not exists last_read_at timestamptz;

alter table public.room_members
  add column if not exists last_read_message_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'room_members_last_read_message_id_fkey'
  ) then
    alter table public.room_members
      add constraint room_members_last_read_message_id_fkey
      foreign key (last_read_message_id)
      references public.room_messages (id)
      on delete set null;
  end if;
end $$;

comment on column public.conversation_member_preferences.last_read_at is
  'Timestamp half of the stable (created_at,id) DM read cursor.';
comment on column public.conversation_member_preferences.last_read_message_id is
  'Message-id half of the stable (created_at,id) DM read cursor.';
comment on column public.room_members.last_read_at is
  'Timestamp half of the stable (created_at,id) Trade Room read cursor.';
comment on column public.room_members.last_read_message_id is
  'Message-id half of the stable (created_at,id) Trade Room read cursor.';

-- ---------------------------------------------------------------------------
-- 3. Backfill cursors from legacy seen_by state
-- ---------------------------------------------------------------------------

-- DM: messages.seen_by is uuid[]
with latest_seen as (
  select distinct on (cp.user_id, m.conversation_id)
    cp.user_id,
    m.conversation_id,
    m.created_at,
    m.id
  from public.conversation_participants cp
  join public.messages m
    on m.conversation_id = cp.conversation_id
   and cp.user_id = any (coalesce(m.seen_by, '{}'::uuid[]))
  order by cp.user_id, m.conversation_id, m.created_at desc, m.id desc
)
insert into public.conversation_member_preferences (
  user_id,
  conversation_id,
  last_read_at,
  last_read_message_id
)
select user_id, conversation_id, created_at, id
from latest_seen
on conflict (user_id, conversation_id) do update
set
  last_read_at = coalesce(
    public.conversation_member_preferences.last_read_at,
    excluded.last_read_at
  ),
  last_read_message_id = case
    when public.conversation_member_preferences.last_read_at is null
      then excluded.last_read_message_id
    else public.conversation_member_preferences.last_read_message_id
  end;

-- Rooms: room_messages.seen_by is jsonb (array of uuid strings).
-- room_members PK is (room_id, user_id) — no surrogate id column.
with latest_seen as (
  select distinct on (rm.user_id, msg.room_id)
    rm.user_id,
    rm.room_id,
    msg.created_at,
    msg.id as message_id
  from public.room_members rm
  join public.room_messages msg
    on msg.room_id = rm.room_id
   and coalesce(msg.seen_by, '[]'::jsonb) ? rm.user_id::text
  where rm.left_at is null
  order by rm.user_id, msg.room_id, msg.created_at desc, msg.id desc
)
update public.room_members rm
set
  last_read_at = latest_seen.created_at,
  last_read_message_id = latest_seen.message_id
from latest_seen
where rm.room_id = latest_seen.room_id
  and rm.user_id = latest_seen.user_id
  and rm.last_read_at is null;

-- ---------------------------------------------------------------------------
-- 4. Cursor / pagination indexes
-- ---------------------------------------------------------------------------

create index if not exists messages_conversation_cursor_idx
  on public.messages (conversation_id, created_at desc, id desc);

create index if not exists room_messages_room_cursor_idx
  on public.room_messages (room_id, created_at desc, id desc);

create index if not exists room_messages_section_cursor_idx
  on public.room_messages (room_id, section_id, pinned, created_at desc, id desc);

create index if not exists conversation_member_preferences_read_cursor_idx
  on public.conversation_member_preferences (
    user_id,
    conversation_id,
    last_read_at,
    last_read_message_id
  );

create index if not exists messages_sender_conversation_created_at_idx
  on public.messages (sender_id, created_at desc)
  where conversation_id is not null
    and coalesce(is_system, false) = false;

-- ---------------------------------------------------------------------------
-- 5. DM read / unread RPCs  (messages.seen_by = uuid[])
-- ---------------------------------------------------------------------------

create or replace function public.mark_conversation_read(
  p_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_latest record;
begin
  if v_user_id is null
     or not public.is_conversation_participant(p_conversation_id, v_user_id) then
    raise exception 'conversation_access_denied' using errcode = '42501';
  end if;

  select m.id, m.created_at
  into v_latest
  from public.messages m
  where m.conversation_id = p_conversation_id
  order by m.created_at desc, m.id desc
  limit 1;

  insert into public.conversation_member_preferences (
    user_id,
    conversation_id,
    last_read_at,
    last_read_message_id
  )
  values (
    v_user_id,
    p_conversation_id,
    v_latest.created_at,
    v_latest.id
  )
  on conflict (user_id, conversation_id) do update
  set
    last_read_at = excluded.last_read_at,
    last_read_message_id = excluded.last_read_message_id,
    updated_at = now()
  where public.conversation_member_preferences.last_read_at is null
     or (
       public.conversation_member_preferences.last_read_at,
       coalesce(
         public.conversation_member_preferences.last_read_message_id,
         'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid
       )
     ) < (excluded.last_read_at, excluded.last_read_message_id);

  -- Preserve the existing "Seen" receipt without rewriting every historical row.
  if v_latest.id is not null then
    update public.messages m
    set seen_by = coalesce(m.seen_by, '{}'::uuid[]) || array[v_user_id]
    where m.id = v_latest.id
      and m.sender_id is distinct from v_user_id
      and not (v_user_id = any (coalesce(m.seen_by, '{}'::uuid[])));
  end if;
end;
$$;

create or replace function public.mark_conversation_unread(
  p_conversation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_target record;
  v_predecessor record;
begin
  if v_user_id is null
     or not public.is_conversation_participant(p_conversation_id, v_user_id) then
    raise exception 'conversation_access_denied' using errcode = '42501';
  end if;

  select m.id, m.created_at
  into v_target
  from public.messages m
  where m.conversation_id = p_conversation_id
    and m.sender_id is not null
    and m.sender_id <> v_user_id
  order by m.created_at desc, m.id desc
  limit 1;

  if v_target.id is null then
    return null;
  end if;

  select m.id, m.created_at
  into v_predecessor
  from public.messages m
  where m.conversation_id = p_conversation_id
    and (m.created_at, m.id) < (v_target.created_at, v_target.id)
  order by m.created_at desc, m.id desc
  limit 1;

  insert into public.conversation_member_preferences (
    user_id,
    conversation_id,
    last_read_at,
    last_read_message_id
  )
  values (
    v_user_id,
    p_conversation_id,
    v_predecessor.created_at,
    v_predecessor.id
  )
  on conflict (user_id, conversation_id) do update
  set
    last_read_at = excluded.last_read_at,
    last_read_message_id = excluded.last_read_message_id,
    updated_at = now();

  update public.messages m
  set seen_by = array_remove(coalesce(m.seen_by, '{}'::uuid[]), v_user_id)
  where m.id = v_target.id
    and v_user_id = any (coalesce(m.seen_by, '{}'::uuid[]));

  return v_target.id;
end;
$$;

create or replace function public.get_conversation_unread_counts(
  p_conversation_ids uuid[] default null
)
returns table (conversation_id uuid, unread_count bigint)
language sql
stable
security definer
set search_path = public
as $$
  select
    cp.conversation_id,
    count(m.id)::bigint as unread_count
  from public.conversation_participants cp
  left join public.conversation_member_preferences prefs
    on prefs.user_id = cp.user_id
   and prefs.conversation_id = cp.conversation_id
  left join public.messages m
    on m.conversation_id = cp.conversation_id
   and m.sender_id is not null
   and m.sender_id <> cp.user_id
   and (
     prefs.last_read_at is null
     or (m.created_at, m.id) >
        (prefs.last_read_at, coalesce(prefs.last_read_message_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid))
   )
  where cp.user_id = auth.uid()
    and (p_conversation_ids is null or cp.conversation_id = any(p_conversation_ids))
  group by cp.conversation_id;
$$;

-- ---------------------------------------------------------------------------
-- 6. Room read / unread RPCs  (room_messages.seen_by = jsonb)
-- ---------------------------------------------------------------------------

create or replace function public.mark_room_read(
  p_room_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_latest record;
begin
  if v_user_id is null then
    raise exception 'room_access_denied' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.room_members rm
    where rm.room_id = p_room_id
      and rm.user_id = v_user_id
      and rm.left_at is null
  ) then
    raise exception 'room_access_denied' using errcode = '42501';
  end if;

  select msg.id, msg.created_at
  into v_latest
  from public.room_messages msg
  where msg.room_id = p_room_id
  order by msg.created_at desc, msg.id desc
  limit 1;

  update public.room_members
  set
    last_read_at = v_latest.created_at,
    last_read_message_id = v_latest.id
  where room_id = p_room_id
    and user_id = v_user_id
    and left_at is null
    and (
      last_read_at is null
      or (
        last_read_at,
        coalesce(last_read_message_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)
      ) < (v_latest.created_at, v_latest.id)
    );

  -- Preserve a latest-message room receipt using jsonb array membership.
  if v_latest.id is not null then
    update public.room_messages msg
    set seen_by =
      coalesce(msg.seen_by, '[]'::jsonb)
      || jsonb_build_array(v_user_id::text)
    where msg.id = v_latest.id
      and msg.user_id <> v_user_id
      and not (coalesce(msg.seen_by, '[]'::jsonb) ? v_user_id::text);
  end if;
end;
$$;

create or replace function public.get_room_unread_counts(
  p_room_ids uuid[] default null
)
returns table (room_id uuid, unread_count bigint)
language sql
stable
security definer
set search_path = public
as $$
  select
    rm.room_id,
    count(msg.id)::bigint as unread_count
  from public.room_members rm
  left join public.room_messages msg
    on msg.room_id = rm.room_id
   and msg.user_id <> rm.user_id
   and (
     rm.last_read_at is null
     or (msg.created_at, msg.id) >
        (rm.last_read_at, coalesce(rm.last_read_message_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid))
   )
  where rm.user_id = auth.uid()
    and rm.left_at is null
    and (p_room_ids is null or rm.room_id = any(p_room_ids))
  group by rm.room_id;
$$;

-- ---------------------------------------------------------------------------
-- 7. Grants
-- ---------------------------------------------------------------------------

revoke all on function public.mark_conversation_read(uuid) from public;
revoke all on function public.mark_conversation_unread(uuid) from public;
revoke all on function public.get_conversation_unread_counts(uuid[]) from public;
revoke all on function public.mark_room_read(uuid) from public;
revoke all on function public.get_room_unread_counts(uuid[]) from public;

grant execute on function public.mark_conversation_read(uuid) to authenticated;
grant execute on function public.mark_conversation_unread(uuid) to authenticated;
grant execute on function public.get_conversation_unread_counts(uuid[]) to authenticated;
grant execute on function public.mark_room_read(uuid) to authenticated;
grant execute on function public.get_room_unread_counts(uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Ops helper: rate_limit_counters retention
-- ---------------------------------------------------------------------------

create or replace function public.rate_limit_cleanup_counters(
  p_retain interval default interval '48 hours'
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_count integer;
begin
  delete from public.rate_limit_counters
  where window_start < now() - p_retain;
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

comment on function public.rate_limit_cleanup_counters(interval) is
  'Deletes stale rate_limit_counters rows older than the retain window.';

revoke all on function public.rate_limit_cleanup_counters(interval) from public;
