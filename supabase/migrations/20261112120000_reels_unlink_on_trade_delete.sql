-- Preserve standalone clips when a journal trade is deleted; clear stale trade_id.

alter table public.reels
  drop constraint if exists reels_trade_id_fkey;

alter table public.reels
  add constraint reels_trade_id_fkey
  foreign key (trade_id)
  references public.trades (id)
  on delete set null;

comment on column public.reels.trade_id is
  'Optional link to a journal trade; cleared when the trade is deleted (clip remains).';

create or replace function public.delete_own_trade(p_trade_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_owner uuid;
  v_account_id text;
  v_can_add boolean;
  v_post_ids uuid[];
  v_message_ids uuid[];
begin
  if p_trade_id is null then
    raise exception 'Trade id is required';
  end if;

  select user_id, nullif(trim(account_id::text), '')
  into v_owner, v_account_id
  from public.trades
  where id = p_trade_id;

  if v_owner is null then
    raise exception 'Trade not found';
  end if;

  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if v_owner is distinct from auth.uid() then
    raise exception 'Not authorized to delete this trade';
  end if;

  if v_account_id is not null
     and not public.profile_trade_slots_pro_for_user(v_owner)
     and public.free_plan_limits_enforced() then
    if public.free_plan_trade_slots_pending(v_owner) then
      raise exception 'ACCOUNT_SLOT_SELECTION_REQUIRED';
    end if;

    select a.can_add_trades
    into v_can_add
    from public.accounts a
    where a.id::text = v_account_id
      and a.user_id = v_owner;

    if found and v_can_add is not true then
      raise exception 'ACCOUNT_READ_ONLY';
    end if;
  end if;

  -- Detach trade-linked clips (do not delete the reel).
  update public.reels
  set trade_id = null,
      kind = null,
      updated_at = now()
  where trade_id = p_trade_id;

  select coalesce(array_agg(id), '{}'::uuid[])
  into v_post_ids
  from public.posts
  where trade_id = p_trade_id;

  if coalesce(array_length(v_post_ids, 1), 0) > 0 then
    delete from public.likes where post_id = any (v_post_ids);
    delete from public.comments where post_id = any (v_post_ids);

    if to_regclass('public.saved_posts') is not null then
      delete from public.saved_posts where post_id = any (v_post_ids);
    end if;

    delete from public.notifications where post_id = any (v_post_ids);
    delete from public.posts where id = any (v_post_ids);
  end if;

  delete from public.notifications where trade_id = p_trade_id;
  delete from public.trade_likes where trade_id = p_trade_id;
  delete from public.trade_comments where trade_id = p_trade_id;

  if to_regclass('public.saved_trades') is not null then
    delete from public.saved_trades where trade_id = p_trade_id;
  end if;

  select coalesce(array_agg(id), '{}'::uuid[])
  into v_message_ids
  from public.messages
  where trade_id = p_trade_id;

  if coalesce(array_length(v_message_ids, 1), 0) > 0 then
    if to_regclass('public.message_likes') is not null then
      delete from public.message_likes where message_id = any (v_message_ids);
    end if;

    if to_regclass('public.message_comments') is not null then
      delete from public.message_comments where message_id = any (v_message_ids);
    end if;

    delete from public.messages where id = any (v_message_ids);
  end if;

  if to_regclass('public.room_messages') is not null then
    delete from public.room_messages where trade_id = p_trade_id;
    update public.room_messages
    set pinned_trade_id = null
    where pinned_trade_id = p_trade_id;
  end if;

  delete from public.trades where id = p_trade_id;
end;
$$;

comment on function public.delete_own_trade(uuid) is
  'Deletes a trade owned by auth.uid(), detaches linked reels (clips remain), feed posts, engagement, notifications, and shares.';

notify pgrst, 'reload schema';
