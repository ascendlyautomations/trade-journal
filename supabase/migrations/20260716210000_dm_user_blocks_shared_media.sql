-- Direct-message user blocking and cursor-paginated shared message media.
-- Blocking applies only to 1:1 conversations; group chats are intentionally unaffected.

create table if not exists public.user_blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint user_blocks_pkey primary key (blocker_id, blocked_id),
  constraint user_blocks_no_self check (blocker_id <> blocked_id)
);

create index if not exists user_blocks_blocked_id_idx
  on public.user_blocks (blocked_id, blocker_id);

alter table public.user_blocks enable row level security;

drop policy if exists "user_blocks_select_own" on public.user_blocks;
create policy "user_blocks_select_own"
  on public.user_blocks
  for select
  to authenticated
  using (blocker_id = auth.uid());

-- Writes are intentionally RPC-only so callers cannot forge the blocker id.
revoke all on table public.user_blocks from anon, authenticated;
grant select on table public.user_blocks to authenticated;

create or replace function public.users_have_active_block(
  p_user_a uuid,
  p_user_b uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_blocks ub
    where (ub.blocker_id = p_user_a and ub.blocked_id = p_user_b)
       or (ub.blocker_id = p_user_b and ub.blocked_id = p_user_a)
  );
$$;

revoke all on function public.users_have_active_block(uuid, uuid) from public;
grant execute on function public.users_have_active_block(uuid, uuid) to authenticated;

create or replace function public.get_dm_block_status(p_conversation_id uuid)
returns table (
  other_user_id uuid,
  blocked_by_me boolean,
  blocked_by_other boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  peer uuid;
begin
  if caller is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.conversations c
    where c.id = p_conversation_id
      and coalesce(c.is_group, false) = false
  ) or not public.is_conversation_participant(p_conversation_id, caller) then
    raise exception 'Direct conversation not available';
  end if;

  select cp.user_id
  into peer
  from public.conversation_participants cp
  where cp.conversation_id = p_conversation_id
    and cp.user_id <> caller
  order by cp.user_id
  limit 1;

  if peer is null then
    raise exception 'Direct conversation peer not available';
  end if;

  return query
  select
    peer,
    exists (
      select 1 from public.user_blocks ub
      where ub.blocker_id = caller and ub.blocked_id = peer
    ),
    exists (
      select 1 from public.user_blocks ub
      where ub.blocker_id = peer and ub.blocked_id = caller
    );
end;
$$;

revoke all on function public.get_dm_block_status(uuid) from public;
grant execute on function public.get_dm_block_status(uuid) to authenticated;

create or replace function public.set_dm_user_block(
  p_conversation_id uuid,
  p_blocked boolean
)
returns table (
  other_user_id uuid,
  blocked_by_me boolean,
  blocked_by_other boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  peer uuid;
begin
  if caller is null then
    raise exception 'Authentication required';
  end if;

  select s.other_user_id
  into peer
  from public.get_dm_block_status(p_conversation_id) s;

  if p_blocked then
    insert into public.user_blocks (blocker_id, blocked_id)
    values (caller, peer)
    on conflict (blocker_id, blocked_id) do nothing;
  else
    delete from public.user_blocks
    where blocker_id = caller
      and blocked_id = peer;
  end if;

  return query
  select * from public.get_dm_block_status(p_conversation_id);
end;
$$;

revoke all on function public.set_dm_user_block(uuid, boolean) from public;
grant execute on function public.set_dm_user_block(uuid, boolean) to authenticated;

-- Blocked DMs are hidden only from the user who initiated the block.
create or replace function public.get_hidden_blocked_dm_conversation_ids()
returns table (conversation_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select distinct mine.conversation_id
  from public.user_blocks ub
  join public.conversation_participants mine
    on mine.user_id = ub.blocker_id
  join public.conversation_participants peer
    on peer.conversation_id = mine.conversation_id
   and peer.user_id = ub.blocked_id
  join public.conversations c
    on c.id = mine.conversation_id
   and coalesce(c.is_group, false) = false
  where ub.blocker_id = auth.uid();
$$;

revoke all on function public.get_hidden_blocked_dm_conversation_ids() from public;
grant execute on function public.get_hidden_blocked_dm_conversation_ids() to authenticated;

-- Reject message sends in either direction while a DM block is active.
create or replace function public.messages_reject_blocked_dm_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  peer uuid;
begin
  if new.conversation_id is null or new.channel is not null then
    return new;
  end if;

  if exists (
    select 1
    from public.conversations c
    where c.id = new.conversation_id
      and coalesce(c.is_group, false) = false
  ) then
    select cp.user_id
    into peer
    from public.conversation_participants cp
    where cp.conversation_id = new.conversation_id
      and cp.user_id <> auth.uid()
    order by cp.user_id
    limit 1;

    if peer is not null and public.users_have_active_block(auth.uid(), peer) then
      raise exception using
        errcode = 'P0001',
        message = 'Direct messages are unavailable while this user is blocked.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists messages_reject_blocked_dm_insert_trigger
  on public.messages;
create trigger messages_reject_blocked_dm_insert_trigger
  before insert on public.messages
  for each row
  execute function public.messages_reject_blocked_dm_insert();

-- Prevent bypass by creating another direct conversation while either user blocks the other.
create or replace function public.conversation_participants_reject_blocked_dm_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_peer uuid;
begin
  if exists (
    select 1
    from public.conversations c
    where c.id = new.conversation_id
      and coalesce(c.is_group, false) = false
  ) then
    for existing_peer in
      select cp.user_id
      from public.conversation_participants cp
      where cp.conversation_id = new.conversation_id
        and cp.user_id <> new.user_id
    loop
      if public.users_have_active_block(new.user_id, existing_peer) then
        raise exception using
          errcode = 'P0001',
          message = 'A direct conversation cannot be created while a user block is active.';
      end if;
    end loop;
  end if;

  return new;
end;
$$;

drop trigger if exists conversation_participants_reject_blocked_dm_insert_trigger
  on public.conversation_participants;
create trigger conversation_participants_reject_blocked_dm_insert_trigger
  before insert on public.conversation_participants
  for each row
  execute function public.conversation_participants_reject_blocked_dm_insert();

-- Compact newest-first shared-media scan. The RPC independently verifies membership,
-- excludes globally deleted and caller-hidden rows, and caps every page at 12.
create index if not exists messages_shared_media_cursor_idx
  on public.messages (conversation_id, created_at desc, id desc)
  where image_url is not null and coalesce(deleted_for_everyone, false) = false;

create or replace function public.get_conversation_shared_media(
  p_conversation_id uuid,
  p_before_created_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 12
)
returns table (
  message_id uuid,
  sender_id uuid,
  image_url text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  page_size integer := least(greatest(coalesce(p_limit, 12), 1), 12);
begin
  if caller is null
     or not public.is_conversation_participant(p_conversation_id, caller) then
    raise exception 'Conversation media is available to current members only';
  end if;

  return query
  select m.id, m.sender_id, m.image_url, m.created_at
  from public.messages m
  where m.conversation_id = p_conversation_id
    and m.image_url is not null
    and btrim(m.image_url) <> ''
    and coalesce(m.deleted_for_everyone, false) = false
    and not exists (
      select 1
      from public.message_deletions md
      where md.message_id = m.id
        and md.user_id = caller
    )
    and (
      p_before_created_at is null
      or (m.created_at, m.id) < (p_before_created_at, p_before_id)
    )
  order by m.created_at desc, m.id desc
  limit page_size;
end;
$$;

revoke all on function public.get_conversation_shared_media(uuid, timestamptz, uuid, integer)
  from public;
grant execute on function public.get_conversation_shared_media(uuid, timestamptz, uuid, integer)
  to authenticated;
