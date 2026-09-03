-- DM privacy ("Who can message me") and profile-level user blocking.
-- Reuses public.user_blocks + existing DM block RPCs/triggers from 20260716210000.

alter table public.profiles
  add column if not exists dm_privacy text not null default 'everyone';

alter table public.profiles
  drop constraint if exists profiles_dm_privacy_check;

alter table public.profiles
  add constraint profiles_dm_privacy_check
  check (dm_privacy in ('everyone', 'following', 'followers', 'mutual'));

comment on column public.profiles.dm_privacy is
  'Who may start a new 1:1 DM with this user: everyone | following | followers | mutual';

create or replace function public.recipient_allows_dm(
  p_sender uuid,
  p_recipient uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  privacy text;
  follows_recipient boolean;
  followed_by_recipient boolean;
begin
  if p_sender is null or p_recipient is null or p_sender = p_recipient then
    return false;
  end if;

  select coalesce(p.dm_privacy, 'everyone')
  into privacy
  from public.profiles p
  where p.id = p_recipient;

  if privacy is null or privacy = 'everyone' then
    return true;
  end if;

  select exists (
    select 1
    from public.followers f
    where f.follower_id = p_sender
      and f.following_id = p_recipient
  )
  into follows_recipient;

  select exists (
    select 1
    from public.followers f
    where f.follower_id = p_recipient
      and f.following_id = p_sender
  )
  into followed_by_recipient;

  case privacy
    when 'following' then return follows_recipient;
    when 'followers' then return followed_by_recipient;
    when 'mutual' then return follows_recipient and followed_by_recipient;
    else return true;
  end case;
end;
$$;

revoke all on function public.recipient_allows_dm(uuid, uuid) from public;
grant execute on function public.recipient_allows_dm(uuid, uuid) to authenticated;

create or replace function public.get_user_block_status(p_other_user_id uuid)
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
begin
  if caller is null then
    raise exception 'Authentication required';
  end if;

  if p_other_user_id is null or p_other_user_id = caller then
    raise exception 'Invalid user';
  end if;

  return query
  select
    p_other_user_id,
    exists (
      select 1 from public.user_blocks ub
      where ub.blocker_id = caller and ub.blocked_id = p_other_user_id
    ),
    exists (
      select 1 from public.user_blocks ub
      where ub.blocker_id = p_other_user_id and ub.blocked_id = caller
    );
end;
$$;

revoke all on function public.get_user_block_status(uuid) from public;
grant execute on function public.get_user_block_status(uuid) to authenticated;

create or replace function public.set_user_block(
  p_blocked_id uuid,
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
begin
  if caller is null then
    raise exception 'Authentication required';
  end if;

  if p_blocked_id is null or p_blocked_id = caller then
    raise exception 'Invalid user';
  end if;

  if p_blocked then
    insert into public.user_blocks (blocker_id, blocked_id)
    values (caller, p_blocked_id)
    on conflict (blocker_id, blocked_id) do nothing;
  else
    delete from public.user_blocks
    where blocker_id = caller
      and blocked_id = p_blocked_id;
  end if;

  return query
  select * from public.get_user_block_status(p_blocked_id);
end;
$$;

revoke all on function public.set_user_block(uuid, boolean) from public;
grant execute on function public.set_user_block(uuid, boolean) to authenticated;

create or replace function public.list_muted_dm_peers()
returns table (
  conversation_id uuid,
  peer_id uuid,
  username text,
  name text,
  avatar_url text
)
language sql
stable
security definer
set search_path = public
as $$
  select distinct on (peer.user_id)
    cmp.conversation_id,
    peer.user_id as peer_id,
    p.username,
    p.name,
    p.avatar_url
  from public.conversation_member_preferences cmp
  join public.conversation_participants mine
    on mine.conversation_id = cmp.conversation_id
   and mine.user_id = auth.uid()
  join public.conversations c
    on c.id = cmp.conversation_id
   and coalesce(c.is_group, false) = false
  join public.conversation_participants peer
    on peer.conversation_id = cmp.conversation_id
   and peer.user_id <> auth.uid()
  join public.profiles p
    on p.id = peer.user_id
  where cmp.user_id = auth.uid()
    and cmp.notifications_enabled = false
  order by peer.user_id, cmp.conversation_id;
$$;

revoke all on function public.list_muted_dm_peers() from public;
grant execute on function public.list_muted_dm_peers() to authenticated;

-- Enforce recipient DM privacy when joining a new 1:1 conversation.
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
    if new.user_id <> auth.uid()
       and not public.recipient_allows_dm(auth.uid(), new.user_id) then
      raise exception using
        errcode = 'P0001',
        message = 'Direct messaging is not available for this user.';
    end if;

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

      if existing_peer <> auth.uid()
         and not public.recipient_allows_dm(auth.uid(), existing_peer) then
        raise exception using
          errcode = 'P0001',
          message = 'Direct messaging is not available for this user.';
      end if;
    end loop;
  end if;

  return new;
end;
$$;
