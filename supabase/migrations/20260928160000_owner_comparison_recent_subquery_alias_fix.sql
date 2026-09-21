-- Phase 8G follow-up: recent-ticker aggregate referenced alias `s` outside subquery scope.

create or replace function public.rpc_v1_trade_detail_owner_comparison(p_trade_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_trade public.trades%rowtype;
  v_root_ticker text;
  v_current_pnl numeric;
  v_current_rr numeric;
  v_current_hold int;
  v_cohort jsonb := null;
  v_ticker jsonb := null;
  v_cohort_count int := 0;
  v_cohort_avg_pnl numeric := null;
  v_cohort_avg_rr numeric := null;
  v_cohort_avg_hold numeric := null;
  v_cohort_pnl_percentile numeric := null;
  v_cohort_rr_percentile numeric := null;
  v_cohort_hold_shorter_pct numeric := null;
  v_prev_ticker_count int := 0;
  v_prev_ticker_wins int := 0;
  v_prev_ticker_total_pnl numeric := 0;
  v_prev_ticker_gross_wins numeric := 0;
  v_prev_ticker_gross_losses numeric := 0;
  v_prev_ticker_avg numeric := null;
  v_prev_ticker_pf numeric := null;
  v_prev_ticker_better int := 0;
  v_recent_wins int := 0;
  v_recent_count int := 0;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select *
  into v_trade
  from public.trades t
  where t.id::text = trim(p_trade_id)
  limit 1;

  if not found then
    raise exception 'trade_not_found' using errcode = 'P0002';
  end if;

  if v_trade.user_id is distinct from v_uid then
    return jsonb_build_object(
      'meta', jsonb_build_object(
        'contract_version', 'v1',
        'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'viewer_id', v_uid::text
      ),
      'data', jsonb_build_object(
        'cohort', null,
        'ticker_history', null
      )
    );
  end if;

  v_root_ticker := public.normalize_trade_ticker(v_trade.ticker);
  v_current_pnl := coalesce(v_trade.pnl, 0);
  v_current_rr := v_trade.rr;
  v_current_hold := coalesce(
    nullif(v_trade.duration_seconds, 0),
    case
      when nullif(trim(v_trade.exit_time), '') is not null
        and nullif(trim(v_trade.entry_time), '') is not null
        then greatest(
          0,
          extract(
            epoch from (
              nullif(trim(v_trade.exit_time), '')::timestamptz
              - nullif(trim(v_trade.entry_time), '')::timestamptz
            )
          )::int
        )
      else null
    end
  );

  select
    count(*)::int,
    avg(s.pnl),
    avg(s.rr) filter (where s.rr is not null),
    avg(s.hold_seconds) filter (where s.hold_seconds is not null)
  into v_cohort_count, v_cohort_avg_pnl, v_cohort_avg_rr, v_cohort_avg_hold
  from public.owner_comparison_scope_trades(v_uid) s
  where s.id::text <> trim(p_trade_id);

  if v_cohort_count >= 5 then
    select
      (count(*) filter (where s.pnl < v_current_pnl)::numeric / nullif(count(*), 0)) * 100,
      (count(*) filter (where s.rr is not null and s.rr < v_current_rr)::numeric
        / nullif(count(*) filter (where s.rr is not null), 0)) * 100,
      (count(*) filter (where s.hold_seconds is not null and s.hold_seconds > v_current_hold)::numeric
        / nullif(count(*) filter (where s.hold_seconds is not null), 0)) * 100
    into v_cohort_pnl_percentile, v_cohort_rr_percentile, v_cohort_hold_shorter_pct
    from public.owner_comparison_scope_trades(v_uid) s
    where s.id::text <> trim(p_trade_id);

    v_cohort := jsonb_build_object(
      'trade_count', v_cohort_count,
      'avg_pnl', coalesce(v_cohort_avg_pnl, 0),
      'avg_rr', v_cohort_avg_rr,
      'avg_hold_seconds', v_cohort_avg_hold,
      'pnl_percentile', v_cohort_pnl_percentile,
      'rr_percentile', v_cohort_rr_percentile,
      'hold_shorter_than_percent', v_cohort_hold_shorter_pct
    );
  end if;

  if v_root_ticker <> '' then
    select
      count(*)::int,
      count(*) filter (where s.pnl > 0)::int,
      coalesce(sum(s.pnl), 0),
      coalesce(sum(s.pnl) filter (where s.pnl > 0), 0),
      coalesce(sum(s.pnl) filter (where s.pnl < 0), 0),
      count(*) filter (where s.pnl < v_current_pnl)::int
    into
      v_prev_ticker_count,
      v_prev_ticker_wins,
      v_prev_ticker_total_pnl,
      v_prev_ticker_gross_wins,
      v_prev_ticker_gross_losses,
      v_prev_ticker_better
    from public.owner_comparison_scope_trades(v_uid) s
    where s.id::text <> trim(p_trade_id)
      and s.root_ticker = v_root_ticker;

    if v_prev_ticker_count > 0 then
      v_prev_ticker_avg := v_prev_ticker_total_pnl / v_prev_ticker_count;
      if v_prev_ticker_gross_losses < 0 then
        v_prev_ticker_pf := v_prev_ticker_gross_wins / abs(v_prev_ticker_gross_losses);
      end if;
    end if;

    select
      count(*)::int,
      count(*) filter (where recent.pnl > 0)::int
    into v_recent_count, v_recent_wins
    from (
      select s.pnl
      from public.owner_comparison_scope_trades(v_uid) s
      where s.id::text <> trim(p_trade_id)
        and s.root_ticker = v_root_ticker
      order by s.activity_at desc
      limit 10
    ) recent;

    v_ticker := jsonb_build_object(
      'ticker', v_root_ticker,
      'previous_trade_count', v_prev_ticker_count,
      'win_rate', case
        when v_prev_ticker_count > 0 then v_prev_ticker_wins::numeric / v_prev_ticker_count
        else null
      end,
      'total_pnl', v_prev_ticker_total_pnl,
      'profit_factor', v_prev_ticker_pf,
      'avg_trade_pnl', v_prev_ticker_avg,
      'better_than_count', v_prev_ticker_better,
      'recent_wins', v_recent_wins,
      'recent_trade_count', v_recent_count
    );
  end if;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid::text
    ),
    'data', jsonb_build_object(
      'cohort', v_cohort,
      'ticker_history', v_ticker
    )
  );
end;
$$;
