-- rpc_v1_feed_bootstrap failed with 42501 after feed copy-linkage added account_id /
-- source_account_id to SECURITY INVOKER _v1_feed_post_trade_payload (20261005010000).
-- Callers must not SELECT protected trade columns; definer helpers enforce viewer rules.

-- ---------------------------------------------------------------------------
-- Feed trade card payload (post rows). Output contract unchanged.
-- ---------------------------------------------------------------------------

create or replace function public._v1_feed_post_trade_payload(
  p_trade_id uuid,
  p_reel public.reels,
  p_guest boolean
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_trade public.trades%rowtype;
begin
  if p_trade_id is null then
    return null;
  end if;

  select * into v_trade
  from public.trades t
  where t.id = p_trade_id;

  if v_trade.id is null then
    return null;
  end if;

  if public.viewer_has_block_with(v_trade.user_id) then
    return null;
  end if;

  if not public.profile_is_visible_to_viewer(v_trade.user_id) then
    return null;
  end if;

  if coalesce(p_guest, false) then
    if coalesce(v_trade.is_public, false) = false then
      return null;
    end if;
    if not exists (
      select 1
      from public.profiles pr
      where pr.id = v_trade.user_id
        and coalesce(pr.is_private, false) = false
    ) then
      return null;
    end if;

    return jsonb_build_object(
      'created_at', v_trade.created_at,
      'public_description', v_trade.public_description,
      'user_id', v_trade.user_id,
      'ticker', v_trade.ticker,
      'direction', v_trade.direction,
      'account_type', v_trade.account_type,
      'mode', v_trade.mode,
      'trade_mode', v_trade.trade_mode,
      'points', v_trade.points,
      'entry_time', v_trade.entry_time,
      'exit_time', v_trade.exit_time,
      'entry_price', v_trade.entry_price,
      'exit_price', v_trade.exit_price,
      'trade_date', v_trade.trade_date,
      'duration_seconds', v_trade.duration_seconds,
      'duration_text', v_trade.duration_text,
      'image_url', v_trade.image_url,
      'image_crop', v_trade.image_crop,
      'is_public', true,
      'reels', case
        when p_reel.id is null or coalesce(p_reel.visibility, 'public') <> 'public' then null
        else jsonb_build_object(
          'id', p_reel.id,
          'user_id', p_reel.user_id,
          'video_url', p_reel.video_url,
          'thumbnail_url', p_reel.thumbnail_url,
          'duration_seconds', p_reel.duration_seconds,
          'trade_id', p_reel.trade_id,
          'visibility', p_reel.visibility
        )
      end
    );
  end if;

  if auth.uid() is distinct from v_trade.user_id
     and not (
       coalesce(v_trade.is_public, false)
       and public.profile_viewer_can_view_trades(v_trade.user_id)
     )
  then
    return null;
  end if;

  return jsonb_build_object(
    'created_at', v_trade.created_at,
    'public_description', v_trade.public_description,
    'user_id', v_trade.user_id,
    'account_id', v_trade.account_id,
    'source_account_id', v_trade.source_account_id,
    'ticker', v_trade.ticker,
    'direction', v_trade.direction,
    'account_type', v_trade.account_type,
    'mode', v_trade.mode,
    'trade_mode', v_trade.trade_mode,
    'copied_account_ids', v_trade.copied_account_ids,
    'copy_trading_group_id', v_trade.copy_trading_group_id,
    'points', v_trade.points,
    'entry_time', v_trade.entry_time,
    'exit_time', v_trade.exit_time,
    'entry_price', v_trade.entry_price,
    'exit_price', v_trade.exit_price,
    'trade_date', v_trade.trade_date,
    'duration_seconds', v_trade.duration_seconds,
    'duration_text', v_trade.duration_text,
    'image_url', v_trade.image_url,
    'image_crop', v_trade.image_crop,
    'reels', case when p_reel.id is null then null else jsonb_build_object(
      'id', p_reel.id,
      'user_id', p_reel.user_id,
      'video_url', p_reel.video_url,
      'thumbnail_url', p_reel.thumbnail_url,
      'duration_seconds', p_reel.duration_seconds,
      'trade_id', p_reel.trade_id,
      'visibility', p_reel.visibility
    ) end
  );
end;
$$;

comment on function public._v1_feed_post_trade_payload(uuid, public.reels, boolean) is
  'Feed trade card JSON. SECURITY DEFINER reads trades; enforces blocks, profile visibility, and public/follower trade rules.';

revoke all on function public._v1_feed_post_trade_payload(uuid, public.reels, boolean) from public;
grant execute on function public._v1_feed_post_trade_payload(uuid, public.reels, boolean) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- rpc_v1_feed_bootstrap — guest trade filter uses trades_public_read (invoker-safe).
-- ---------------------------------------------------------------------------

do $mig$
declare
  src text;
  updated text;
begin
  select pg_get_functiondef(p.oid)
  into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_feed_bootstrap'
    and pg_get_function_identity_arguments(p.oid) =
      'p_scope text, p_content_filter text, p_limit integer, p_cursor text';

  if src is null then
    raise exception 'rpc_v1_feed_bootstrap was not found';
  end if;

  updated := src;

  if position('left join public.trades t on t.id = p.trade_id' in updated) > 0 then
    updated := replace(
      updated,
      'left join public.trades t on t.id = p.trade_id',
      ''
    );
  end if;

  if position('public._v1_feed_post_trade_payload(t, tr, v_guest)' in updated) > 0 then
    updated := replace(
      updated,
      'public._v1_feed_post_trade_payload(t, tr, v_guest)',
      'public._v1_feed_post_trade_payload(p.trade_id, tr, v_guest)'
    );
  end if;

  if position('from public.trades tx' in updated) > 0 then
    updated := replace(
      updated,
      E'from public.trades tx\n                where tx.id = p.trade_id\n                  and coalesce(tx.is_public, false) = true',
      E'from public.trades_public_read tx\n                where tx.id = p.trade_id'
    );
  end if;

  if updated = src then
    if position('public._v1_feed_post_trade_payload(p.trade_id, tr, v_guest)' in src) = 0 then
      raise exception 'rpc_v1_feed_bootstrap trade payload call was not found';
    end if;
    if position('left join public.trades t on t.id = p.trade_id' in src) > 0 then
      raise exception 'rpc_v1_feed_bootstrap trades join was not removed';
    end if;
    if position('from public.trades tx' in src) > 0
       and position('from public.trades_public_read tx' in src) = 0 then
      raise exception 'rpc_v1_feed_bootstrap guest trade filter still reads public.trades';
    end if;
    return;
  end if;

  if position('security definer' in lower(updated)) > 0 then
    raise exception 'rpc_v1_feed_bootstrap must stay security invoker';
  end if;
  if position('users_have_active_block' in updated) = 0 then
    raise exception 'rpc_v1_feed_bootstrap block filter was not preserved';
  end if;

  execute updated;
end
$mig$;
