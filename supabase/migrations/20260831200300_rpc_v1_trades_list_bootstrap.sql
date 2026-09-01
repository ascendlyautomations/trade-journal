-- Phase 2: Trade History list bootstrap — filtered owner trades + accounts snapshot.

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
      t.strategy
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
            'strategy', r.strategy
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

revoke all on function public.rpc_v1_trades_list_bootstrap(
  int, text, text, text, text, timestamptz, timestamptz, text, numeric, numeric, text, text
) from public;
grant execute on function public.rpc_v1_trades_list_bootstrap(
  int, text, text, text, text, timestamptz, timestamptz, text, numeric, numeric, text, text
) to authenticated;

comment on function public.rpc_v1_trades_list_bootstrap is
  'Phase 2 Trade History bootstrap — owner accounts + filtered keyset-paginated trades.';
