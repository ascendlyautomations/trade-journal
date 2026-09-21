-- Phase 8D — owner Journal trades list V2 (TradeSummary + owner extension). V1 unchanged.

create or replace function public.trade_summary_owner_extension_json(
  p_trade public.trades
)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select jsonb_strip_nulls(
    jsonb_build_object(
      'account_id', nullif(trim(coalesce(p_trade.account_id, '')), ''),
      'account_name', nullif(trim(coalesce(p_trade.account_name, '')), ''),
      'strategy', nullif(trim(coalesce(p_trade.strategy, '')), ''),
      'entry_price', p_trade.entry_price,
      'exit_price', p_trade.exit_price,
      'session', nullif(trim(coalesce(p_trade.session, '')), '')
    )
  );
$$;

create or replace function public.trade_summary_owner_journal_json(
  p_trade public.trades,
  p_viewer_id uuid
)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select public.trade_summary_json(p_trade, p_viewer_id)
    || public.trade_summary_owner_extension_json(p_trade);
$$;

comment on function public.trade_summary_owner_journal_json(public.trades, uuid) is
  'Phase 8D owner Journal list row — canonical TradeSummary + owner-list extension.';

create or replace function public.rpc_v1_trades_list_bootstrap_v2(
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
  p_rr_min numeric default null,
  p_rr_max numeric default null,
  p_direction text default 'any',
  p_visibility text default 'any',
  p_account_mode text default 'all',
  p_session text default 'all'
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
  v_cursor_rr numeric;
  v_account_mode text := lower(trim(coalesce(p_account_mode, 'all')));
  v_session text := lower(trim(coalesce(p_session, 'all')));
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  case v_sort
    when 'oldest' then
      v_order_col := 'created_at';
      v_asc := true;
    when 'highestpnl', 'highest_pnl', 'bestwin', 'best_win' then
      v_order_col := 'pnl';
      v_asc := false;
    when 'lowestpnl', 'lowest_pnl', 'worstloss', 'worst_loss' then
      v_order_col := 'pnl';
      v_asc := true;
    when 'highestrr', 'highest_rr' then
      v_order_col := 'rr';
      v_asc := false;
    when 'lowestrr', 'lowest_rr' then
      v_order_col := 'rr';
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
    elsif v_order_col = 'rr' then
      begin
        v_cursor_rr := trim(p_cursor)::numeric;
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
      and (p_rr_min is null or coalesce(t.rr, 0) >= p_rr_min)
      and (p_rr_max is null or coalesce(t.rr, 0) <= p_rr_max)
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
        v_account_mode = 'all'
        or (
          v_account_mode = 'live'
          and lower(trim(coalesce(t.account_type, t.mode, ''))) = 'live'
        )
        or (
          v_account_mode = 'funded'
          and lower(trim(coalesce(t.account_type, t.mode, ''))) = 'funded'
        )
        or (
          v_account_mode in ('eval', 'evaluation')
          and lower(trim(coalesce(t.account_type, t.mode, ''))) in ('eval', 'evaluation')
        )
      )
      and (
        v_session = 'all'
        or lower(trim(coalesce(t.session, ''))) = v_session
      )
      and (
        p_search is null
        or trim(p_search) = ''
        or t.ticker ilike '%' || trim(p_search) || '%'
        or t.notes ilike '%' || trim(p_search) || '%'
        or t.account_name ilike '%' || trim(p_search) || '%'
        or t.strategy ilike '%' || trim(p_search) || '%'
        or t.session ilike '%' || trim(p_search) || '%'
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
        or (
          v_order_col = 'rr'
          and v_cursor_rr is not null
          and (
            (v_asc and coalesce(t.rr, 0) > v_cursor_rr)
            or (not v_asc and coalesce(t.rr, 0) < v_cursor_rr)
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
      case when v_order_col = 'rr' and v_asc then f.rr end asc nulls last,
      case when v_order_col = 'rr' and not v_asc then f.rr end desc nulls last,
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
          public.trade_summary_owner_journal_json(tr, v_uid)
          order by
            case when v_order_col = 'pnl' and v_asc then tr.pnl end asc nulls last,
            case when v_order_col = 'pnl' and not v_asc then tr.pnl end desc nulls last,
            case when v_order_col = 'rr' and v_asc then tr.rr end asc nulls last,
            case when v_order_col = 'rr' and not v_asc then tr.rr end desc nulls last,
            case when v_order_col = 'created_at' and v_asc then tr.created_at end asc nulls last,
            case when v_order_col = 'created_at' and not v_asc then tr.created_at end desc nulls last,
            tr.id desc
        )
        from trimmed r
        inner join public.trades tr on tr.id = r.id
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
          when v_order_col = 'rr' then (
            select coalesce(r.rr::text, to_char(r.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
            from trimmed r
            order by r.rr desc nulls last, r.created_at desc
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
      'contract_version', 'v2',
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

comment on function public.rpc_v1_trades_list_bootstrap_v2(
  int, text, text, text, text, timestamptz, timestamptz, text, numeric, numeric, numeric, numeric, text, text, text, text
) is
  'Phase 8D owner Journal list — TradeSummary + owner extension; V1 bootstrap unchanged.';

revoke all on function public.rpc_v1_trades_list_bootstrap_v2(int, text, text, text, text, timestamptz, timestamptz, text, numeric, numeric, numeric, numeric, text, text, text, text) from public;
grant execute on function public.rpc_v1_trades_list_bootstrap_v2(int, text, text, text, text, timestamptz, timestamptz, text, numeric, numeric, numeric, numeric, text, text, text, text) to authenticated;

