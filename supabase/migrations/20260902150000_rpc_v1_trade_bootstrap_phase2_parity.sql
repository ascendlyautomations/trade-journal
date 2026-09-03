-- Phase 2 Add Trade parity: extend owner bootstrap RPC trade payloads with
-- image_display_mode and full journal metadata on Trade History bootstrap.

create or replace function public.rpc_v1_dashboard_bootstrap(
  p_account_id uuid default null,
  p_trade_limit integer default 500
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_limit integer := greatest(1, least(coalesce(p_trade_limit, 500), 2000));
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  with ctx as (
    select v_uid as uid, v_limit as lim, p_account_id as account_id
  ),
  scoped_trades as materialized (
    select t.*
    from public.trades t
    cross join ctx
    where t.user_id = ctx.uid
      and (ctx.account_id is null or t.account_id = ctx.account_id::text)
  ),
  live_trades as materialized (
    select st.*
    from scoped_trades st
    where lower(trim(coalesce(st.mode, ''))) is distinct from 'backtest'
      and lower(trim(coalesce(st.account_type, ''))) is distinct from 'backtest'
  ),
  trade_stats as (
    select
      count(*)::integer as total_count,
      min(st.created_at) as oldest_created
    from scoped_trades st
  ),
  trade_window_json as (
    select coalesce(jsonb_agg(row_to_json(w)::jsonb), '[]'::jsonb) as trades
    from (
      select
        st.id,
        st.date,
        st.direction,
        st.pnl,
        st.notes,
        st.created_at,
        st.image_url,
        st.image_display_mode,
        st.ticker,
        st.rr,
        st.points,
        st.session,
        st.account_type,
        st.account_id,
        st.user_id,
        st.account_size,
        st.entry_price,
        st.exit_price,
        st.entry_time,
        st.exit_time,
        st.contracts,
        st.reviewed,
        st.confidence,
        st.emotion,
        st.followed_plan,
        st.mistake_type,
        st.market_condition,
        st.news_event,
        st.timeframe,
        st.psychology_notes,
        st.trade_type,
        st.public_description,
        st.is_pinned,
        st.account_name,
        st.mode,
        st.strategy,
        st.duration_seconds,
        st.duration_text,
        st.is_public,
        st.account_category,
        st.top_confluences,
        st.trade_date,
        st.is_initial_import,
        st.copy_trading_group_id,
        st.trade_mode,
        st.source_account_id,
        st.copied_account_ids
      from scoped_trades st
      order by st.created_at desc nulls last, st.id desc
      limit (select lim from ctx)
    ) w
  ),
  metrics_json as (
    select jsonb_build_object(
      'total_trades', count(*)::integer,
      'wins', count(*) filter (where coalesce(lt.pnl, 0) > 0)::integer,
      'losses', count(*) filter (where coalesce(lt.pnl, 0) < 0)::integer,
      'win_rate', case
        when count(*) = 0 then null
        else round(
          (count(*) filter (where coalesce(lt.pnl, 0) > 0))::numeric
          / count(*)::numeric,
          6
        )
      end,
      'net_pnl', coalesce(sum(lt.pnl), 0),
      'avg_rr', avg(lt.rr),
      'avg_win', avg(lt.pnl) filter (where coalesce(lt.pnl, 0) > 0),
      'avg_loss', avg(lt.pnl) filter (where coalesce(lt.pnl, 0) < 0),
      'biggest_win', max(lt.pnl),
      'biggest_loss', min(lt.pnl)
    ) as metrics
    from live_trades lt
  ),
  equity_json as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object('t', x.ts, 'v', x.equity)
        order by x.rn
      ),
      '[]'::jsonb
    ) as equity
    from (
      select s.rn, s.ts, s.equity
      from (
        select
          row_number() over (order by lt.created_at asc nulls last, lt.id asc) as rn,
          count(*) over () as cnt,
          to_char(lt.created_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') as ts,
          sum(coalesce(lt.pnl, 0)) over (
            order by lt.created_at asc nulls last, lt.id asc
            rows between unbounded preceding and current row
          ) as equity
        from live_trades lt
      ) s
      where s.rn = 1
         or s.rn = s.cnt
         or s.rn % greatest(1, ceil(s.cnt::numeric / 366.0)::integer) = 0
    ) x
  ),
  accounts_json as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', a.id,
          'account_number', a.account_number,
          'name', a.name,
          'account_size', a.account_size,
          'mode', a.mode,
          'category', a.category,
          'is_active', coalesce(a.is_active, true),
          'can_add_trades', a.can_add_trades,
          'note', a.note,
          'consistency', a.consistency,
          'max_drawdown', a.max_drawdown,
          'daily_drawdown', a.daily_drawdown,
          'profit_target', a.profit_target,
          'winning_days', a.winning_days,
          'winning_day_threshold', a.winning_day_threshold,
          'show_in_account_dropdowns', coalesce(a.show_in_account_dropdowns, true),
          'custom_public_status', a.custom_public_status,
          'payout_drawdown_behavior', a.payout_drawdown_behavior,
          'remember_payout_drawdown_behavior', a.remember_payout_drawdown_behavior
        )
        order by a.created_at asc nulls last, a.id asc
      ),
      '[]'::jsonb
    ) as accounts
    from public.accounts a
    cross join ctx
    where a.user_id = ctx.uid
      and (ctx.account_id is null or a.id = ctx.account_id)
  ),
  payout_json as (
    select coalesce(sum(a.value_numeric), 0) as payout_total
    from public.achievements a
    cross join ctx
    where a.user_id = ctx.uid
      and coalesce(a.is_public, false) = true
      and lower(trim(coalesce(a.achievement_type, ''))) in (
        'prop_firm_payout',
        'live_trading_payout',
        'payout'
      )
  ),
  recent_json as (
    select coalesce(jsonb_agg(elem), '[]'::jsonb) as recent
    from (
      select elem
      from trade_window_json tw,
        jsonb_array_elements(tw.trades) with ordinality as t(elem, ord)
      where ord <= 5
    ) s
  )
  select jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid
    ),
    'data', jsonb_build_object(
      'accounts', aj.accounts,
      'trade_window', tw.trades,
      'trade_window_meta', jsonb_build_object(
        'limit', v_limit,
        'returned', jsonb_array_length(tw.trades),
        'history_complete',
          (ts.total_count <= jsonb_array_length(tw.trades))
          or (jsonb_array_length(tw.trades) < v_limit),
        'total_trade_count', ts.total_count,
        'oldest_created_at', case
          when ts.oldest_created is null then null
          else to_char(ts.oldest_created, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        end,
        'next_cursor', null
      ),
      'metrics', mj.metrics,
      'equity_points', ej.equity,
      'payout_total', pj.payout_total,
      'recent_trades', rj.recent
    )
  )
  into v_result
  from ctx
  cross join trade_stats ts
  cross join trade_window_json tw
  cross join metrics_json mj
  cross join equity_json ej
  cross join accounts_json aj
  cross join payout_json pj
  cross join recent_json rj;

  return v_result;
end;
$$;

create or replace function public.rpc_v1_calendar_bootstrap(
  p_year int,
  p_month int,
  p_account_id uuid default null,
  p_entry_from timestamptz default null,
  p_entry_to timestamptz default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_accounts jsonb := '[]'::jsonb;
  v_trades jsonb := '[]'::jsonb;
  v_net_pnl numeric := 0;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', a.id,
        'account_number', a.account_number,
        'name', a.name,
        'account_size', a.account_size,
        'mode', a.mode,
        'category', a.category,
        'is_active', coalesce(a.is_active, true),
        'can_add_trades', a.can_add_trades,
        'note', a.note,
        'consistency', a.consistency,
        'max_drawdown', a.max_drawdown,
        'daily_drawdown', a.daily_drawdown,
        'profit_target', a.profit_target,
        'winning_days', a.winning_days,
        'winning_day_threshold', a.winning_day_threshold,
        'show_in_account_dropdowns', coalesce(a.show_in_account_dropdowns, true),
        'custom_public_status', a.custom_public_status,
        'payout_drawdown_behavior', a.payout_drawdown_behavior,
        'remember_payout_drawdown_behavior', a.remember_payout_drawdown_behavior
      )
      order by a.created_at asc nulls last, a.id asc
    ),
    '[]'::jsonb
  )
  into v_accounts
  from public.accounts a
  where a.user_id = v_uid;

  with parsed as (
    select
      t.id,
      t.date,
      t.direction,
      t.pnl,
      t.notes,
      t.created_at,
      t.image_url,
      t.ticker,
      t.rr,
      t.points,
      t.session,
      t.account_type,
      t.account_id,
      t.user_id,
      t.account_size,
      t.entry_price,
      t.exit_price,
      t.entry_time,
      t.exit_time,
      t.contracts,
      t.reviewed,
      t.confidence,
      t.emotion,
      t.followed_plan,
      t.mistake_type,
      t.market_condition,
      t.news_event,
      t.timeframe,
      t.psychology_notes,
      t.trade_type,
      t.public_description,
      t.is_pinned,
      t.account_name,
      t.mode,
      t.strategy,
      t.duration_seconds,
      t.duration_text,
      t.image_display_mode,
      t.is_public,
      t.account_category,
      t.top_confluences,
      t.trade_date,
      t.is_initial_import,
      t.copy_trading_group_id,
      t.trade_mode,
      t.source_account_id,
      t.copied_account_ids,
      case
        when nullif(trim(t.entry_time), '') is null then null
        else nullif(trim(t.entry_time), '')::timestamptz
      end as entry_ts,
      case
        when nullif(trim(t.exit_time), '') is null then null
        else nullif(trim(t.exit_time), '')::timestamptz
      end as exit_ts
    from public.trades t
    where t.user_id = v_uid
      and coalesce(lower(trim(t.mode)), '') <> 'backtest'
      and (
        p_account_id is null
        or nullif(trim(t.account_id), '') = p_account_id::text
      )
  ),
  scoped as (
    select p.*
    from parsed p
    where (p_entry_from is null or (p.entry_ts is not null and p.entry_ts >= p_entry_from))
      and (p_entry_to is null or (p.entry_ts is not null and p.entry_ts <= p_entry_to))
    order by p.entry_ts asc nulls last, p.created_at asc
    limit 500
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', s.id,
          'date', s.date,
          'direction', s.direction,
          'pnl', s.pnl,
          'notes', s.notes,
          'created_at', to_char(s.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'image_url', s.image_url,
          'ticker', s.ticker,
          'rr', s.rr,
          'points', s.points,
          'session', s.session,
          'account_type', s.account_type,
          'account_id', s.account_id,
          'user_id', s.user_id,
          'account_size', s.account_size,
          'entry_price', s.entry_price,
          'exit_price', s.exit_price,
          'entry_time', case
            when s.entry_ts is null then null
            else to_char(s.entry_ts at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
          end,
          'exit_time', case
            when s.exit_ts is null then null
            else to_char(s.exit_ts at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
          end,
          'contracts', s.contracts,
          'reviewed', s.reviewed,
          'confidence', s.confidence,
          'emotion', s.emotion,
          'followed_plan', s.followed_plan,
          'mistake_type', s.mistake_type,
          'market_condition', s.market_condition,
          'news_event', s.news_event,
          'timeframe', s.timeframe,
          'psychology_notes', s.psychology_notes,
          'trade_type', s.trade_type,
          'public_description', s.public_description,
          'is_pinned', s.is_pinned,
          'account_name', s.account_name,
          'mode', s.mode,
          'strategy', s.strategy,
          'duration_seconds', s.duration_seconds,
          'duration_text', s.duration_text,
          'image_display_mode', s.image_display_mode,
          'is_public', s.is_public,
          'account_category', s.account_category,
          'top_confluences', s.top_confluences,
          'trade_date', s.trade_date,
          'is_initial_import', s.is_initial_import,
          'copy_trading_group_id', s.copy_trading_group_id,
          'trade_mode', s.trade_mode,
          'source_account_id', s.source_account_id,
          'copied_account_ids', s.copied_account_ids
        )
      ),
      '[]'::jsonb
    ),
    coalesce(sum(coalesce(s.pnl, 0)), 0)
  into v_trades, v_net_pnl
  from scoped s;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid::text
    ),
    'data', jsonb_build_object(
      'year', p_year,
      'month', p_month,
      'accounts', v_accounts,
      'trades', v_trades,
      'metrics_month', jsonb_build_object('net_pnl', v_net_pnl)
    )
  );
end;
$$;

create or replace function public.rpc_v1_trades_list_bootstrap(
  p_limit int default 40,
  p_cursor text default null,
  p_account_id text default null,
  p_search text default null,
  p_sort text default 'newest',
  p_created_from timestamptz default null,
  p_created_to timestamptz default null,
  p_result text default 'any',
  p_pnl_min numeric default null,
  p_pnl_max numeric default null,
  p_direction text default 'any',
  p_visibility text default 'any'
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_limit int := greatest(least(coalesce(p_limit, 40), 100), 1);
  v_accounts jsonb := '[]'::jsonb;
  v_trades jsonb := '[]'::jsonb;
  v_next_cursor text := null;
  v_sort text := lower(trim(coalesce(p_sort, 'newest')));
  v_order_col text := 'created_at';
  v_asc boolean := false;
  v_cursor_ts timestamptz;
  v_cursor_pnl numeric;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  case v_sort
    when 'oldest' then
      v_order_col := 'created_at';
      v_asc := true;
    when 'highestpnl', 'highest_pnl' then
      v_order_col := 'pnl';
      v_asc := false;
    when 'lowestpnl', 'lowest_pnl' then
      v_order_col := 'pnl';
      v_asc := true;
    else
      v_order_col := 'created_at';
      v_asc := false;
  end case;

  if p_cursor is not null and trim(p_cursor) <> '' then
    if v_order_col = 'pnl' then
      begin
        v_cursor_pnl := trim(p_cursor)::numeric;
      exception when others then
        v_cursor_ts := trim(p_cursor)::timestamptz;
        v_order_col := 'created_at';
      end;
    else
      begin
        v_cursor_ts := trim(p_cursor)::timestamptz;
      exception when others then
        v_cursor_ts := null;
      end;
    end if;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', a.id,
        'account_number', a.account_number,
        'name', a.name,
        'account_size', a.account_size,
        'mode', a.mode,
        'category', a.category,
        'is_active', coalesce(a.is_active, true),
        'can_add_trades', a.can_add_trades,
        'note', a.note,
        'consistency', a.consistency,
        'max_drawdown', a.max_drawdown,
        'daily_drawdown', a.daily_drawdown,
        'profit_target', a.profit_target,
        'winning_days', a.winning_days,
        'winning_day_threshold', a.winning_day_threshold,
        'show_in_account_dropdowns', coalesce(a.show_in_account_dropdowns, true),
        'custom_public_status', a.custom_public_status,
        'payout_drawdown_behavior', a.payout_drawdown_behavior,
        'remember_payout_drawdown_behavior', a.remember_payout_drawdown_behavior
      )
      order by a.created_at asc nulls last, a.id asc
    ),
    '[]'::jsonb
  )
  into v_accounts
  from public.accounts a
  where a.user_id = v_uid;

  with filtered as (
    select
      t.id,
      t.user_id,
      t.account_id,
      t.account_name,
      t.created_at,
      t.date,
      t.trade_date,
      t.pnl,
      t.rr,
      t.points,
      t.contracts,
      t.session,
      t.ticker,
      t.direction,
      t.notes,
      t.public_description,
      t.is_public,
      t.is_pinned,
      t.image_url,
      t.entry_time,
      t.exit_time,
      t.entry_price,
      t.exit_price,
      t.account_type,
      t.mode,
      t.strategy,
      t.confidence,
      t.emotion,
      t.followed_plan,
      t.market_condition,
      t.timeframe,
      t.news_event,
      t.psychology_notes,
      t.duration_seconds,
      t.duration_text,
      t.trade_mode,
      t.image_display_mode,
      t.reviewed,
      t.is_initial_import
    from public.trades t
    where t.user_id = v_uid
      and coalesce(lower(trim(t.mode)), '') <> 'backtest'
      and (
        p_account_id is null
        or nullif(trim(p_account_id), '') is null
        or nullif(trim(t.account_id), '') = trim(p_account_id)
      )
      and (
        p_visibility is null
        or lower(trim(p_visibility)) = 'any'
        or (lower(trim(p_visibility)) = 'public' and coalesce(t.is_public, false) = true)
        or (lower(trim(p_visibility)) = 'private' and coalesce(t.is_public, false) = false)
      )
      and (p_created_from is null or t.created_at >= p_created_from)
      and (p_created_to is null or t.created_at < p_created_to)
      and (
        p_result is null
        or lower(trim(p_result)) = 'any'
        or (lower(trim(p_result)) = 'wins' and coalesce(t.pnl, 0) > 0)
        or (lower(trim(p_result)) = 'losses' and coalesce(t.pnl, 0) < 0)
        or (lower(trim(p_result)) = 'breakeven' and coalesce(t.pnl, 0) = 0)
      )
      and (p_pnl_min is null or coalesce(t.pnl, 0) >= p_pnl_min)
      and (p_pnl_max is null or coalesce(t.pnl, 0) <= p_pnl_max)
      and (
        p_direction is null
        or lower(trim(p_direction)) = 'any'
        or (
          lower(trim(p_direction)) = 'long'
          and lower(trim(coalesce(t.direction, ''))) in ('long', 'buy')
        )
        or (
          lower(trim(p_direction)) = 'short'
          and lower(trim(coalesce(t.direction, ''))) in ('short', 'sell')
        )
      )
      and (
        p_search is null
        or trim(p_search) = ''
        or t.ticker ilike '%' || trim(p_search) || '%'
        or t.notes ilike '%' || trim(p_search) || '%'
        or t.account_name ilike '%' || trim(p_search) || '%'
        or t.strategy ilike '%' || trim(p_search) || '%'
      )
      and (
        p_cursor is null
        or trim(p_cursor) = ''
        or (
          v_order_col = 'created_at'
          and (
            (v_asc and t.created_at > v_cursor_ts)
            or (not v_asc and t.created_at < v_cursor_ts)
          )
        )
        or (
          v_order_col = 'pnl'
          and v_cursor_pnl is not null
          and (
            (v_asc and coalesce(t.pnl, 0) > v_cursor_pnl)
            or (not v_asc and coalesce(t.pnl, 0) < v_cursor_pnl)
          )
        )
      )
  ),
  ordered as (
    select *
    from filtered f
    order by
      case when v_order_col = 'pnl' and v_asc then f.pnl end asc nulls last,
      case when v_order_col = 'pnl' and not v_asc then f.pnl end desc nulls last,
      case when v_order_col = 'created_at' and v_asc then f.created_at end asc nulls last,
      case when v_order_col = 'created_at' and not v_asc then f.created_at end desc nulls last,
      f.id desc
    limit v_limit + 1
  ),
  trimmed as (
    select * from ordered
    limit v_limit
  ),
  page_meta as (
    select count(*) as cnt from ordered
  )
  select
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'user_id', r.user_id,
            'account_id', r.account_id,
            'account_name', r.account_name,
            'created_at', to_char(r.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'date', r.date,
            'trade_date', r.trade_date,
            'pnl', r.pnl,
            'rr', r.rr,
            'points', r.points,
            'contracts', r.contracts,
            'session', r.session,
            'ticker', r.ticker,
            'direction', r.direction,
            'notes', r.notes,
            'public_description', r.public_description,
            'is_public', r.is_public,
            'is_pinned', r.is_pinned,
            'image_url', r.image_url,
            'entry_time', to_char(r.entry_time at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'exit_time', to_char(r.exit_time at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'entry_price', r.entry_price,
            'exit_price', r.exit_price,
            'account_type', r.account_type,
            'mode', r.mode,
            'strategy', r.strategy,
            'confidence', r.confidence,
            'emotion', r.emotion,
            'followed_plan', r.followed_plan,
            'market_condition', r.market_condition,
            'timeframe', r.timeframe,
            'news_event', r.news_event,
            'psychology_notes', r.psychology_notes,
            'duration_seconds', r.duration_seconds,
            'duration_text', r.duration_text,
            'trade_mode', r.trade_mode,
            'image_display_mode', r.image_display_mode,
            'reviewed', r.reviewed,
            'is_initial_import', r.is_initial_import
          )
        )
        from trimmed r
      ),
      '[]'::jsonb
    ),
    case
      when (select cnt from page_meta) > v_limit then
        case
          when v_order_col = 'pnl' then (
            select coalesce(r.pnl::text, to_char(r.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
            from trimmed r
            order by r.pnl desc nulls last, r.created_at desc
            offset v_limit - 1
            limit 1
          )
          else (
            select to_char(r.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
            from trimmed r
            order by r.created_at desc
            offset v_limit - 1
            limit 1
          )
        end
      else null
    end
  into v_trades, v_next_cursor;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid::text
    ),
    'data', jsonb_build_object(
      'accounts', v_accounts,
      'trades', v_trades,
      'next_cursor', v_next_cursor,
      'page_meta', jsonb_build_object(
        'limit', v_limit,
        'returned', jsonb_array_length(v_trades),
        'has_more', v_next_cursor is not null
      )
    )
  );
end;
$$;

comment on function public.rpc_v1_dashboard_bootstrap(uuid, integer) is
  'Dashboard bootstrap — trade_window includes image_display_mode for native screenshot display parity.';

comment on function public.rpc_v1_calendar_bootstrap(int, int, uuid, timestamptz, timestamptz) is
  'Calendar bootstrap — trade rows include image_display_mode for native screenshot display parity.';

comment on function public.rpc_v1_trades_list_bootstrap(
  int, text, text, text, text, timestamptz, timestamptz, text, numeric, numeric, text, text
) is
  'Trade History bootstrap — owner journal + psychology + duration + image_display_mode parity.';
