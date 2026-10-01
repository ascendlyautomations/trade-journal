-- Authenticated lost table SELECT on public.trades in
-- 20260930163000_trades_authenticated_journal_privacy.sql. Column grants remain
-- the social projection only. SECURITY INVOKER functions that expand a whole
-- trades row, or that read notes/account_id, then fail with
-- 42501 permission denied for table trades.
--
-- Feed stays SECURITY INVOKER so RLS, blocks, and public/follower visibility
-- still apply. It must not materialize public.trades as a composite.
-- Owner-scoped RPCs that already filter to auth.uid() become SECURITY DEFINER
-- so they can read the caller's journal columns without restoring table SELECT.

-- ---------------------------------------------------------------------------
-- Feed trade card: granted social columns only. Missing or RLS-hidden rows
-- return null, matching the previous left join.
-- ---------------------------------------------------------------------------

create or replace function public._v1_feed_post_trade_payload(
  p_trade_id uuid,
  p_reel public.reels,
  p_guest boolean
)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $fn$
  select case
    when t.id is null then null
    when p_guest and coalesce(t.is_public, false) = false then null
    when p_guest then jsonb_build_object(
      'created_at', t.created_at,
      'public_description', t.public_description,
      'user_id', t.user_id,
      'ticker', t.ticker,
      'direction', t.direction,
      'account_type', t.account_type,
      'mode', t.mode,
      'trade_mode', t.trade_mode,
      'points', t.points,
      'entry_time', t.entry_time,
      'exit_time', t.exit_time,
      'entry_price', t.entry_price,
      'exit_price', t.exit_price,
      'trade_date', t.trade_date,
      'duration_seconds', t.duration_seconds,
      'duration_text', t.duration_text,
      'image_url', t.image_url,
      'image_crop', t.image_crop,
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
    )
    else jsonb_build_object(
      'created_at', t.created_at,
      'public_description', t.public_description,
      'user_id', t.user_id,
      'ticker', t.ticker,
      'direction', t.direction,
      'account_type', t.account_type,
      'mode', t.mode,
      'trade_mode', t.trade_mode,
      'copied_account_ids', t.copied_account_ids,
      'copy_trading_group_id', t.copy_trading_group_id,
      'points', t.points,
      'entry_time', t.entry_time,
      'exit_time', t.exit_time,
      'entry_price', t.entry_price,
      'exit_price', t.exit_price,
      'trade_date', t.trade_date,
      'duration_seconds', t.duration_seconds,
      'duration_text', t.duration_text,
      'image_url', t.image_url,
      'image_crop', t.image_crop,
      'reels', case when p_reel.id is null then null else jsonb_build_object(
        'id', p_reel.id,
        'user_id', p_reel.user_id,
        'video_url', p_reel.video_url,
        'thumbnail_url', p_reel.thumbnail_url,
        'duration_seconds', p_reel.duration_seconds,
        'trade_id', p_reel.trade_id,
        'visibility', p_reel.visibility
      ) end
    )
  end
  from (
    select
      id,
      created_at,
      public_description,
      user_id,
      ticker,
      direction,
      account_type,
      mode,
      trade_mode,
      copied_account_ids,
      copy_trading_group_id,
      points,
      entry_time,
      exit_time,
      entry_price,
      exit_price,
      trade_date,
      duration_seconds,
      duration_text,
      image_url,
      image_crop,
      is_public
    from public.trades
    where id = p_trade_id
  ) t;
$fn$;

comment on function public._v1_feed_post_trade_payload(uuid, public.reels, boolean) is
  'Feed trade card from granted social columns. SECURITY INVOKER so trades RLS still applies.';

revoke all on function public._v1_feed_post_trade_payload(uuid, public.reels, boolean) from public;
grant execute on function public._v1_feed_post_trade_payload(uuid, public.reels, boolean) to anon, authenticated;

-- Point feed bootstrap at the column-safe helper and drop the whole-row join.
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

  updated := replace(
    src,
    'left join public.trades t on t.id = p.trade_id',
    ''
  );
  updated := replace(
    updated,
    'public._v1_feed_post_trade_payload(t, tr, v_guest)',
    'public._v1_feed_post_trade_payload(p.trade_id, tr, v_guest)'
  );

  if updated = src then
    raise exception 'rpc_v1_feed_bootstrap trade row expansion was not found';
  end if;
  -- pg_get_functiondef omits SECURITY INVOKER because it is the default.
  if position('security definer' in lower(updated)) > 0 then
    raise exception 'rpc_v1_feed_bootstrap must stay security invoker';
  end if;
  if position('users_have_active_block' in updated) = 0 then
    raise exception 'rpc_v1_feed_bootstrap block filter was not preserved';
  end if;

  execute updated;
end
$mig$;

drop function if exists public._v1_feed_post_trade_payload(public.trades, public.reels, boolean);

-- Owner comparison loads one row by id. Keep it owner-only before the definer
-- read so another user's private trade is not fetched.
do $mig$
declare
  src text;
  updated text;
  needle text := 'where t.id::text = trim(p_trade_id)';
begin
  select pg_get_functiondef(p.oid)
  into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_trade_detail_owner_comparison'
    and pg_get_function_identity_arguments(p.oid) = 'p_trade_id text';

  if src is null then
    raise exception 'rpc_v1_trade_detail_owner_comparison was not found';
  end if;

  if (length(src) - length(replace(src, needle, ''))) / length(needle) <> 1 then
    raise exception 'unexpected owner-comparison trade predicate';
  end if;

  if position('and t.user_id = v_uid' in src) = 0 then
    updated := replace(
      src,
      needle,
      needle || E'\n    and t.user_id = v_uid'
    );
    execute updated;
  end if;
end
$mig$;

-- These functions already restrict rows to auth.uid() and return only that
-- viewer's data. DEFINER lets them read journal columns the role cannot select.
alter function public.rpc_v1_viewer_sync_state() security definer;
alter function public.rpc_v1_calendar_bootstrap(integer, integer, uuid, timestamp with time zone, timestamp with time zone) security definer;
alter function public.rpc_v1_check_in_history_bootstrap(date, date, uuid) security definer;
alter function public.rpc_v1_prop_firm_bootstrap() security definer;
alter function public.rpc_v1_psychology_check_in_window(uuid) security definer;
alter function public.rpc_v1_analytics_calendar_day_trades(date, uuid, text) security definer;
alter function public.rpc_v1_analytics_shadow_compare_range(date, date, uuid, text) security definer;
alter function public.rpc_v1_trade_detail_owner_comparison(text) security definer;
