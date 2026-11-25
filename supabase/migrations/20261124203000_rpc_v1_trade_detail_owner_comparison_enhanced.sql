-- Trade Detail owner comparison v2: multi-cohort filters, target vs realized R:R, richer ticker history.
--
-- Postgres 42P13: cannot change RETURNS TABLE of owner_comparison_scope_trades via CREATE OR REPLACE.
-- Drop dependents first (no CASCADE), recreate in dependency order. Wrapped in one migration txn.

create or replace function public.owner_comparison_canonical_session(p_raw text)
returns text
language sql
immutable
as $$
  with v as (
    select lower(trim(coalesce(p_raw, ''))) as raw
  )
  select case
    when (select raw from v) = '' then null
    when (select raw from v) in ('ny am', 'new york am') then 'NY AM'
    when (select raw from v) in ('ny lunch', 'new york lunch', 'lunch') then 'NY Lunch'
    when (select raw from v) in ('ny pm', 'new york pm', 'pm') then 'NY PM'
    when (select raw from v) in ('london', 'ldn', 'uk') then 'London'
    when (select raw from v) in ('asia', 'asian', 'tokyo') then 'Asia'
    when (select raw from v) = 'after' then 'After'
    when (select raw from v) like '%lunch%'
      and ((select raw from v) like '%ny%' or (select raw from v) like '%new york%') then 'NY Lunch'
    when (select raw from v) like '%pm%'
      and ((select raw from v) like '%ny%' or (select raw from v) like '%new york%') then 'NY PM'
    when (select raw from v) like '%am%'
      and ((select raw from v) like '%ny%' or (select raw from v) like '%new york%') then 'NY AM'
    when (select raw from v) in ('ny', 'new york')
      or ((select raw from v) like '%ny%' and (select raw from v) not like '%london%') then 'NY AM'
    else null
  end;
$$;

drop function if exists public.rpc_v1_trade_detail_owner_comparison(text);

drop function if exists public.owner_comparison_build_cohort_json(
  uuid,
  text,
  numeric,
  numeric,
  numeric,
  integer,
  text,
  text,
  text,
  text
);

drop function if exists public.owner_comparison_scope_trades(uuid);

create or replace function public.owner_comparison_scope_trades(p_viewer uuid)
returns table (
  id uuid,
  pnl numeric,
  rr numeric,
  hold_seconds integer,
  root_ticker text,
  activity_at timestamptz,
  target_rr numeric,
  realized_rr numeric,
  side_key text,
  strategy_key text,
  session_key text,
  account_id text,
  account_mode_key text
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select distinct on (t.id)
    t.id,
    coalesce(t.pnl, 0) as pnl,
    t.rr as rr,
    coalesce(
      nullif(t.duration_seconds, 0),
      case
        when nullif(trim(t.exit_time), '') is not null
          and nullif(trim(t.entry_time), '') is not null
          then greatest(
            0,
            extract(
              epoch from (
                nullif(trim(t.exit_time), '')::timestamptz
                - nullif(trim(t.entry_time), '')::timestamptz
              )
            )::int
          )
        else null
      end
    ) as hold_seconds,
    public.normalize_trade_ticker(t.ticker) as root_ticker,
    coalesce(
      nullif(trim(t.entry_time), '')::timestamptz,
      t.created_at
    ) as activity_at,
    t.rr as target_rr,
    t.realized_rr,
    case lower(trim(coalesce(t.direction, '')))
      when 'long' then 'long'
      when 'buy' then 'long'
      when 'short' then 'short'
      when 'sell' then 'short'
      else null
    end as side_key,
    nullif(lower(trim(coalesce(t.strategy, ''))), '') as strategy_key,
    public.owner_comparison_canonical_session(t.session) as session_key,
    nullif(trim(t.account_id), '') as account_id,
    public.profile_statistics_resolve_account_mode(a.mode, t.account_type, t.mode) as account_mode_key
  from public.trades t
  left join public.accounts a
    on a.id::text = nullif(trim(t.account_id), '')
  where t.user_id = p_viewer
    and coalesce(lower(trim(t.mode)), '') <> 'backtest'
    and coalesce(lower(trim(t.account_type)), '') <> 'backtest'
    and coalesce(lower(trim(a.mode)), '') <> 'backtest'
  order by t.id;
$$;

comment on function public.owner_comparison_scope_trades(uuid) is
  'Owner journal scope rows for trade detail comparison aggregates (no temp tables).';

create or replace function public.owner_comparison_build_cohort_json(
  p_viewer uuid,
  p_exclude_trade_id text,
  p_current_pnl numeric,
  p_current_target_rr numeric,
  p_current_realized_rr numeric,
  p_current_hold integer,
  p_account_id text default null,
  p_account_mode text default null,
  p_strategy_key text default null,
  p_session_key text default null
)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with peers as (
    select s.*
    from public.owner_comparison_scope_trades(p_viewer) s
    where s.id::text <> trim(p_exclude_trade_id)
      and (
        p_account_id is null
        or (
          s.account_id is not distinct from p_account_id
          and s.account_mode_key is not distinct from p_account_mode
        )
      )
      and (p_strategy_key is null or s.strategy_key is not distinct from p_strategy_key)
      and (p_session_key is null or s.session_key is not distinct from p_session_key)
  ),
  agg as (
    select
      count(*)::int as trade_count,
      avg(pnl) as avg_pnl,
      case when count(*) > 0 then count(*) filter (where pnl > 0)::numeric / count(*) else null end as win_rate,
      avg(target_rr) filter (where target_rr is not null) as avg_target_rr,
      avg(realized_rr) filter (where realized_rr is not null) as avg_realized_rr,
      avg(hold_seconds) filter (where hold_seconds is not null) as avg_hold_seconds,
      (count(*) filter (where pnl < p_current_pnl)::numeric / nullif(count(*), 0)) * 100 as pnl_percentile,
      (count(*) filter (where target_rr is not null and target_rr < p_current_target_rr)::numeric
        / nullif(count(*) filter (where target_rr is not null), 0)) * 100 as target_rr_percentile,
      (count(*) filter (where realized_rr is not null and realized_rr < p_current_realized_rr)::numeric
        / nullif(count(*) filter (where realized_rr is not null), 0)) * 100 as realized_rr_percentile,
      (count(*) filter (where hold_seconds is not null and hold_seconds > p_current_hold)::numeric
        / nullif(count(*) filter (where hold_seconds is not null), 0)) * 100 as hold_shorter_than_percent
    from peers
  ),
  sides as (
    select
      count(*) filter (where side_key = 'long')::int as long_count,
      case when count(*) filter (where side_key = 'long') > 0
        then count(*) filter (where side_key = 'long' and pnl > 0)::numeric
          / count(*) filter (where side_key = 'long')
        else null end as long_win_rate,
      avg(pnl) filter (where side_key = 'long') as long_avg_pnl,
      count(*) filter (where side_key = 'short')::int as short_count,
      case when count(*) filter (where side_key = 'short') > 0
        then count(*) filter (where side_key = 'short' and pnl > 0)::numeric
          / count(*) filter (where side_key = 'short')
        else null end as short_win_rate,
      avg(pnl) filter (where side_key = 'short') as short_avg_pnl
    from peers
  ),
  joined as (
    select *
    from agg a
    cross join sides s
  )
  select case
    when trade_count < 5 then null::jsonb
    else jsonb_build_object(
      'trade_count', trade_count,
      'avg_pnl', coalesce(avg_pnl, 0),
      'win_rate', win_rate,
      'avg_rr', avg_target_rr,
      'avg_target_rr', avg_target_rr,
      'avg_realized_rr', avg_realized_rr,
      'avg_hold_seconds', avg_hold_seconds,
      'pnl_percentile', pnl_percentile,
      'rr_percentile', target_rr_percentile,
      'target_rr_percentile', target_rr_percentile,
      'realized_rr_percentile', realized_rr_percentile,
      'hold_shorter_than_percent', hold_shorter_than_percent,
      'long', jsonb_build_object(
        'trade_count', coalesce(long_count, 0),
        'win_rate', long_win_rate,
        'avg_pnl', long_avg_pnl
      ),
      'short', jsonb_build_object(
        'trade_count', coalesce(short_count, 0),
        'win_rate', short_win_rate,
        'avg_pnl', short_avg_pnl
      )
    )
  end
  from joined;
$$;

create or replace function public.rpc_v1_trade_detail_owner_comparison(p_trade_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_trade public.trades%rowtype;
  v_account public.accounts%rowtype;
  v_root_ticker text;
  v_current_pnl numeric;
  v_current_target_rr numeric;
  v_current_realized_rr numeric;
  v_current_hold int;
  v_current_account_id text;
  v_current_account_mode text;
  v_current_strategy_key text;
  v_current_session_key text;
  v_cohort_all jsonb := null;
  v_cohort_account_mode jsonb := null;
  v_cohort_setup jsonb := null;
  v_cohort_session jsonb := null;
  v_cohorts jsonb := null;
  v_ticker jsonb := null;
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
  v_long_count int := 0;
  v_long_wins int := 0;
  v_long_total numeric := 0;
  v_long_avg numeric := null;
  v_short_count int := 0;
  v_short_wins int := 0;
  v_short_total numeric := 0;
  v_short_avg numeric := null;
  v_sessions jsonb := '[]'::jsonb;
  v_window_30d jsonb := null;
  v_window_90d jsonb := null;
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
        'cohorts', null,
        'ticker_history', null
      )
    );
  end if;

  select *
  into v_account
  from public.accounts a
  where a.id::text = nullif(trim(v_trade.account_id), '')
  limit 1;

  v_root_ticker := public.normalize_trade_ticker(v_trade.ticker);
  v_current_pnl := coalesce(v_trade.pnl, 0);
  v_current_target_rr := v_trade.rr;
  v_current_realized_rr := v_trade.realized_rr;
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
  v_current_account_id := nullif(trim(v_trade.account_id), '');
  v_current_account_mode := public.profile_statistics_resolve_account_mode(
    v_account.mode,
    v_trade.account_type,
    v_trade.mode
  );
  v_current_strategy_key := nullif(lower(trim(coalesce(v_trade.strategy, ''))), '');
  v_current_session_key := public.owner_comparison_canonical_session(v_trade.session);

  v_cohort_all := public.owner_comparison_build_cohort_json(
    v_uid,
    p_trade_id,
    v_current_pnl,
    v_current_target_rr,
    v_current_realized_rr,
    v_current_hold
  );

  if v_current_account_id is not null and v_current_account_mode is not null then
    v_cohort_account_mode := public.owner_comparison_build_cohort_json(
      v_uid,
      p_trade_id,
      v_current_pnl,
      v_current_target_rr,
      v_current_realized_rr,
      v_current_hold,
      v_current_account_id,
      v_current_account_mode
    );
  end if;

  if v_current_strategy_key is not null then
    v_cohort_setup := public.owner_comparison_build_cohort_json(
      v_uid,
      p_trade_id,
      v_current_pnl,
      v_current_target_rr,
      v_current_realized_rr,
      v_current_hold,
      null,
      null,
      v_current_strategy_key
    );
  end if;

  if v_current_session_key is not null then
    v_cohort_session := public.owner_comparison_build_cohort_json(
      v_uid,
      p_trade_id,
      v_current_pnl,
      v_current_target_rr,
      v_current_realized_rr,
      v_current_hold,
      null,
      null,
      null,
      v_current_session_key
    );
  end if;

  v_cohorts := jsonb_build_object(
    'all', v_cohort_all,
    'account_mode', v_cohort_account_mode,
    'setup', v_cohort_setup,
    'session', v_cohort_session
  );

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

    select
      count(*) filter (where s.side_key = 'long')::int,
      count(*) filter (where s.side_key = 'long' and s.pnl > 0)::int,
      coalesce(sum(s.pnl) filter (where s.side_key = 'long'), 0),
      count(*) filter (where s.side_key = 'short')::int,
      count(*) filter (where s.side_key = 'short' and s.pnl > 0)::int,
      coalesce(sum(s.pnl) filter (where s.side_key = 'short'), 0)
    into
      v_long_count,
      v_long_wins,
      v_long_total,
      v_short_count,
      v_short_wins,
      v_short_total
    from public.owner_comparison_scope_trades(v_uid) s
    where s.id::text <> trim(p_trade_id)
      and s.root_ticker = v_root_ticker;

    if v_long_count > 0 then
      v_long_avg := v_long_total / v_long_count;
    end if;
    if v_short_count > 0 then
      v_short_avg := v_short_total / v_short_count;
    end if;

    select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.trade_count desc, x.session asc), '[]'::jsonb)
    into v_sessions
    from (
      select
        s.session_key as session,
        count(*)::int as trade_count,
        count(*) filter (where s.pnl > 0)::numeric / nullif(count(*), 0) as win_rate,
        avg(s.pnl) as avg_pnl
      from public.owner_comparison_scope_trades(v_uid) s
      where s.id::text <> trim(p_trade_id)
        and s.root_ticker = v_root_ticker
        and s.session_key is not null
      group by s.session_key
      having count(*) >= 1
      order by count(*) desc, s.session_key asc
      limit 4
    ) x;

    select jsonb_build_object(
      'trade_count', w.trade_count,
      'win_rate', w.win_rate,
      'total_pnl', w.total_pnl,
      'avg_pnl', w.avg_pnl,
      'profit_factor', w.profit_factor
    )
    into v_window_30d
    from (
      select
        count(*)::int as trade_count,
        case when count(*) > 0 then count(*) filter (where s.pnl > 0)::numeric / count(*) else null end as win_rate,
        coalesce(sum(s.pnl), 0) as total_pnl,
        avg(s.pnl) as avg_pnl,
        case
          when coalesce(sum(s.pnl) filter (where s.pnl < 0), 0) < 0 then
            coalesce(sum(s.pnl) filter (where s.pnl > 0), 0)
            / abs(sum(s.pnl) filter (where s.pnl < 0))
          else null
        end as profit_factor
      from public.owner_comparison_scope_trades(v_uid) s
      where s.id::text <> trim(p_trade_id)
        and s.root_ticker = v_root_ticker
        and s.activity_at >= timezone('utc', now()) - interval '30 days'
    ) w
  where w.trade_count > 0;

    select jsonb_build_object(
      'trade_count', w.trade_count,
      'win_rate', w.win_rate,
      'total_pnl', w.total_pnl,
      'avg_pnl', w.avg_pnl,
      'profit_factor', w.profit_factor
    )
    into v_window_90d
    from (
      select
        count(*)::int as trade_count,
        case when count(*) > 0 then count(*) filter (where s.pnl > 0)::numeric / count(*) else null end as win_rate,
        coalesce(sum(s.pnl), 0) as total_pnl,
        avg(s.pnl) as avg_pnl,
        case
          when coalesce(sum(s.pnl) filter (where s.pnl < 0), 0) < 0 then
            coalesce(sum(s.pnl) filter (where s.pnl > 0), 0)
            / abs(sum(s.pnl) filter (where s.pnl < 0))
          else null
        end as profit_factor
      from public.owner_comparison_scope_trades(v_uid) s
      where s.id::text <> trim(p_trade_id)
        and s.root_ticker = v_root_ticker
        and s.activity_at >= timezone('utc', now()) - interval '90 days'
    ) w
  where w.trade_count > 0;

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
      'recent_trade_count', v_recent_count,
      'long', case when v_long_count > 0 then jsonb_build_object(
        'trade_count', v_long_count,
        'win_rate', v_long_wins::numeric / v_long_count,
        'avg_pnl', v_long_avg,
        'total_pnl', v_long_total
      ) else null end,
      'short', case when v_short_count > 0 then jsonb_build_object(
        'trade_count', v_short_count,
        'win_rate', v_short_wins::numeric / v_short_count,
        'avg_pnl', v_short_avg,
        'total_pnl', v_short_total
      ) else null end,
      'sessions', v_sessions,
      'window_30d', v_window_30d,
      'window_90d', v_window_90d
    );
  end if;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid::text
    ),
    'data', jsonb_build_object(
      'cohort', v_cohort_all,
      'cohorts', v_cohorts,
      'ticker_history', v_ticker
    )
  );
end;
$$;

comment on function public.owner_comparison_canonical_session(text) is
  'Canonical trading session label for owner comparison filters (iOS TradingSessionLabel parity).';

comment on function public.owner_comparison_build_cohort_json(
  uuid, text, numeric, numeric, numeric, integer, text, text, text, text
) is
  'Internal cohort aggregate builder for rpc_v1_trade_detail_owner_comparison (not for direct client use).';

comment on function public.rpc_v1_trade_detail_owner_comparison(text) is
  'Owner trade detail comparison aggregates — previous trades only, multi-cohort filters, enriched ticker history.';

revoke all on function public.owner_comparison_scope_trades(uuid) from public;
grant execute on function public.owner_comparison_scope_trades(uuid) to authenticated;

revoke all on function public.rpc_v1_trade_detail_owner_comparison(text) from public;
grant execute on function public.rpc_v1_trade_detail_owner_comparison(text) to authenticated;

revoke all on function public.owner_comparison_build_cohort_json(
  uuid, text, numeric, numeric, numeric, integer, text, text, text, text
) from public;