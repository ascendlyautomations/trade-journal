-- Livestream (Trade Room broadcast) chat: session-scoped private trade share grants.
-- Chat payloads travel over LiveKit; this table is the durable read grant for trade SELECT RLS.
-- Does not set trades.is_public.

create table if not exists public.room_live_broadcast_chat_trade_shares (
  broadcast_session_id uuid not null
    references public.room_live_broadcasts (id) on delete cascade,
  trade_id uuid not null references public.trades (id) on delete cascade,
  shared_by_user_id uuid not null,
  chat_message_id text not null,
  shared_at timestamptz not null default timezone('utc', now()),
  primary key (broadcast_session_id, chat_message_id),
  constraint room_live_broadcast_chat_trade_shares_message_id_len
    check (char_length(chat_message_id) between 1 and 256)
);

create index if not exists room_live_broadcast_chat_trade_shares_trade_idx
  on public.room_live_broadcast_chat_trade_shares (trade_id);

alter table public.room_live_broadcast_chat_trade_shares enable row level security;

comment on table public.room_live_broadcast_chat_trade_shares is
  'Durable grants for trades shared in a livestream chat message (LiveKit message id).';

-- Active room members (not banned / stream-blocked) may use shares on an active or past session they belong to.
create or replace function public.can_read_broadcast_chat_trade_share(p_broadcast_session_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1
    from public.room_live_broadcasts b
    where b.id = p_broadcast_session_id
      and auth.uid() is not null
      and public.is_active_room_member(b.room_id, auth.uid())
      and not public.is_room_banned(b.room_id, auth.uid())
      and not exists (
        select 1
        from public.room_live_broadcast_session_blocks bl
        where bl.broadcast_session_id = b.id
          and bl.user_id = auth.uid()
      )
  );
$$;

comment on function public.can_read_broadcast_chat_trade_share(uuid) is
  'True when auth.uid() may read trades shared in this broadcast session chat.';

revoke all on function public.can_read_broadcast_chat_trade_share(uuid) from public;
grant execute on function public.can_read_broadcast_chat_trade_share(uuid) to authenticated;

drop policy if exists "room_live_broadcast_chat_trade_shares_select_scoped"
  on public.room_live_broadcast_chat_trade_shares;

create policy "room_live_broadcast_chat_trade_shares_select_scoped"
  on public.room_live_broadcast_chat_trade_shares
  for select
  to authenticated
  using (public.can_read_broadcast_chat_trade_share(broadcast_session_id));

-- OR policy: read private (and public) trades explicitly shared in livestream chat.
drop policy if exists "trades_select_shared_in_broadcast_chat" on public.trades;

create policy "trades_select_shared_in_broadcast_chat"
  on public.trades
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.room_live_broadcast_chat_trade_shares s
      where s.trade_id = trades.id
        and public.can_read_broadcast_chat_trade_share(s.broadcast_session_id)
    )
  );

comment on policy "trades_select_shared_in_broadcast_chat" on public.trades is
  'Room members may read trades attached to livestream chat for sessions they can access; does not publish trades.';

-- Register / refresh a share when the owner posts a trade attachment (called from clients after LiveKit send).
create or replace function public.rpc_v1_broadcast_chat_register_trade_share(
  p_broadcast_session_id uuid,
  p_trade_id uuid,
  p_chat_message_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_message_id text;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  v_message_id := nullif(trim(p_chat_message_id), '');
  if v_message_id is null or char_length(v_message_id) > 256 then
    raise exception 'invalid chat message id' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.trades t
    where t.id = p_trade_id
      and t.user_id = auth.uid()
  ) then
    raise exception 'you can only share trades you own' using errcode = '42501';
  end if;

  select b.room_id into v_room_id
  from public.room_live_broadcasts b
  where b.id = p_broadcast_session_id
  limit 1;

  if v_room_id is null then
    raise exception 'broadcast session not found' using errcode = '22023';
  end if;

  if not public.is_active_room_member(v_room_id, auth.uid()) then
    raise exception 'room membership required' using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.room_live_broadcast_session_blocks bl
    where bl.broadcast_session_id = p_broadcast_session_id
      and bl.user_id = auth.uid()
  ) then
    raise exception 'removed from stream' using errcode = '42501';
  end if;

  insert into public.room_live_broadcast_chat_trade_shares (
    broadcast_session_id,
    trade_id,
    shared_by_user_id,
    chat_message_id
  ) values (
    p_broadcast_session_id,
    p_trade_id,
    auth.uid(),
    v_message_id
  )
  on conflict (broadcast_session_id, chat_message_id) do update
  set
    trade_id = excluded.trade_id,
    shared_by_user_id = excluded.shared_by_user_id,
    shared_at = timezone('utc', now());
end;
$$;

comment on function public.rpc_v1_broadcast_chat_register_trade_share(uuid, uuid, text) is
  'Owner registers a livestream chat trade attachment for session-scoped RLS (no is_public change).';

revoke all on function public.rpc_v1_broadcast_chat_register_trade_share(uuid, uuid, text) from public;
grant execute on function public.rpc_v1_broadcast_chat_register_trade_share(uuid, uuid, text) to authenticated;