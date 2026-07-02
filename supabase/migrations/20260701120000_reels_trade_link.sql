-- Trade-linked reels (V1): reels.trade_id + kind; trade owns caption/visibility.

alter table public.reels
  add column if not exists trade_id uuid references public.trades (id) on delete cascade,
  add column if not exists kind text;

create index if not exists reels_trade_id_idx
  on public.reels (trade_id)
  where trade_id is not null;

comment on column public.reels.trade_id is
  'When set, caption and visibility inherit from the parent trade.';
comment on column public.reels.kind is
  'Optional reel role (e.g. execution_replay, recap). Reserved for multi-reel.';

-- Attached reels must not store their own caption.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'reels_trade_caption_check'
  ) then
    alter table public.reels
      add constraint reels_trade_caption_check
      check (trade_id is null or caption is null);
  end if;
end;
$$;

-- =============================================================================
-- RLS: trade-attached reels inherit trade visibility
-- =============================================================================
drop policy if exists reels_select_visible on public.reels;

create policy reels_select_visible
  on public.reels
  for select
  to anon, authenticated
  using (
    -- Standalone reels: existing profile / follower rules
    (
      trade_id is null
      and (
        user_id = auth.uid()
        or exists (
          select 1
          from public.profiles p
          where p.id = reels.user_id
            and coalesce(p.is_private, false) = false
        )
        or (
          auth.uid() is not null
          and exists (
            select 1
            from public.followers f
            where f.following_id = reels.user_id
              and f.follower_id = auth.uid()
          )
        )
      )
    )
    or
    -- Trade-attached: owner always
    (
      trade_id is not null
      and user_id = auth.uid()
    )
    or
    -- Trade-attached: public trade from public profile
    (
      trade_id is not null
      and exists (
        select 1
        from public.trades t
        join public.profiles p on p.id = t.user_id
        where t.id = reels.trade_id
          and t.is_public = true
          and coalesce(p.is_private, false) = false
      )
    )
    or
    -- Trade-attached: public trade on private profile (followers)
    (
      trade_id is not null
      and auth.uid() is not null
      and exists (
        select 1
        from public.trades t
        join public.profiles p on p.id = t.user_id
        where t.id = reels.trade_id
          and t.is_public = true
          and coalesce(p.is_private, false) = true
      )
      and exists (
        select 1
        from public.trades t
        join public.followers f on f.following_id = t.user_id
        where t.id = reels.trade_id
          and f.follower_id = auth.uid()
      )
    )
  );

-- =============================================================================
-- delete_own_trade: cascade trade-attached reels + storage cleanup
-- =============================================================================
create or replace function public.delete_own_trade(p_trade_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_post_ids uuid[];
  v_message_ids uuid[];
  v_reel record;
  v_video_path text;
  v_thumb_path text;
begin
  if p_trade_id is null then
    raise exception 'Trade id is required';
  end if;

  select user_id into v_owner
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

  -- Trade-attached reels: engagement + notifications + messages
  for v_reel in
    select id, video_url, thumbnail_url
    from public.reels
    where trade_id = p_trade_id
  loop
    delete from public.reel_likes where reel_id = v_reel.id;
    delete from public.reel_comments where reel_id = v_reel.id;
    delete from public.notifications where reel_id = v_reel.id;

    if to_regclass('public.messages') is not null then
      delete from public.messages where reel_id = v_reel.id;
    end if;

    delete from public.reels where id = v_reel.id;
  end loop;

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
  'Deletes a trade owned by auth.uid(), attached reels, feed posts, engagement, notifications, and shares.';
