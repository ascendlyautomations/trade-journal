-- Leaderboard: rank and chart in the database.
-- Returns the top window plus daily chart buckets. Does not return raw trades.
-- Visibility matches leaderboard_trade_rows_page: public trades, non-private profiles.

create or replace function public.leaderboard_ranked_window_one(
  p_view text,
  p_account_type text,
  p_now timestamptz,
  p_custom_start timestamptz,
  p_custom_end timestamptz,
  p_custom_start_ymd date,
  p_custom_end_ymd date,
  p_viewer_id uuid,
  p_rank_limit int
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with params as (
    select
      greatest(least(coalesce(p_rank_limit, 25), 25), 1) as rank_limit,
      case
        when lower(btrim(coalesce(p_account_type, 'all'))) in ('funded', 'eval', 'live')
          then lower(btrim(p_account_type))
        else 'all'
      end as account_type,
      coalesce(p_now, now()) as now_at,
      case p_view when '7D' then 7 when '30D' then 30 when '90D' then 90 else null end as window_days
  ),
  bounds as (
    select
      p.*,
      case
        when p.window_days is not null then p.now_at - make_interval(days => p.window_days)
        else null
      end as cutoff_at,
      case
        when p_view = 'YTD' then date_trunc('year', p.now_at at time zone 'America/New_York')::date
        else null
      end as ytd_start,
      case
        when p.window_days is not null
          then ((p.now_at - make_interval(days => p.window_days)) at time zone 'America/New_York')::date
        when p_view = 'YTD'
          then date_trunc('year', p.now_at at time zone 'America/New_York')::date
        when p_view = 'Custom' then p_custom_start_ymd
        else null
      end as chart_start,
      case
        when p_view = 'Custom' then p_custom_end_ymd
        when p_view = 'ALL' then (p.now_at at time zone 'America/New_York')::date
        else (p.now_at at time zone 'America/New_York')::date
      end as chart_end
    from params p
  ),
  eligible as (
    select
      t.user_id,
      t.created_at,
      coalesce(t.pnl, 0)::double precision as pnl,
      t.rr::double precision as rr,
      (t.created_at at time zone 'America/New_York')::date as ny_day
    from public.trades t
    inner join public.profiles pr on pr.id = t.user_id
    cross join bounds b
    where coalesce(pr.is_private, false) = false
      and coalesce(t.is_public, false) = true
      and t.created_at is not null
      and t.user_id is not null
      and (
        b.account_type = 'all'
        or lower(btrim(
          case
            when t.mode is null then coalesce(t.account_type::text, '')
            else t.mode::text
          end
        )) = b.account_type
      )
      and (
        p_view = 'ALL'
        or (b.window_days is not null and t.created_at >= b.cutoff_at)
        or (
          p_view = 'YTD'
          and (t.created_at at time zone 'America/New_York')::date >= b.ytd_start
        )
        or (
          p_view = 'Custom'
          and p_custom_start is not null
          and p_custom_end is not null
          and p_custom_start <= p_custom_end
          and t.created_at >= p_custom_start
          and t.created_at <= p_custom_end
        )
      )
  ),
  totals as (
    select
      count(*)::bigint as trade_count,
      coalesce(sum(pnl), 0) as pnl_sum,
      avg(rr) filter (where rr is not null) as avg_rr
    from eligible
  ),
  yours as (
    select
      count(*)::bigint as trade_count,
      coalesce(sum(pnl), 0) as pnl_sum,
      avg(rr) filter (where rr is not null) as avg_rr
    from eligible
    where user_id = p_viewer_id
  ),
  users as (
    select
      user_id,
      sum(pnl) as total_pnl,
      count(*)::int as trade_count,
      avg(rr) filter (where rr is not null) as avg_rr,
      min(created_at) as first_trade_at
    from eligible
    group by user_id
  ),
  ranked as (
    select
      user_id,
      total_pnl,
      trade_count,
      avg_rr,
      row_number() over (
        order by total_pnl desc, first_trade_at asc, user_id asc
      ) as rank,
      count(*) over () as total_traders
    from users
  ),
  peers as (
    select
      count(*) filter (where user_id is distinct from p_viewer_id) as peer_count,
      count(*) filter (
        where user_id is distinct from p_viewer_id
          and total_pnl < coalesce((
            select total_pnl from users where user_id = p_viewer_id
          ), 0)
      ) as beaten
    from users
  ),
  top_rows as (
    select *
    from ranked
    cross join bounds b
    where rank <= b.rank_limit
  ),
  chart_days as (
    select
      d.ny_day,
      avg(d.pnl) as average,
      max(d.pnl) as best,
      min(d.pnl) as worst,
      coalesce(max(d.pnl) filter (where d.user_id = p_viewer_id), 0) as you,
      count(*)::int as contributor_count
    from (
      select ny_day, user_id, sum(pnl) as pnl
      from eligible
      group by ny_day, user_id
    ) d
    cross join bounds b
    where (
      b.chart_start is null
      or d.ny_day >= greatest(b.chart_start, coalesce((select min(ny_day) from eligible), b.chart_start))
    )
      and (b.chart_end is null or d.ny_day <= b.chart_end)
    group by d.ny_day
  )
  select case
    when (select trade_count from totals) = 0 then jsonb_build_object(
      'hasData', false,
      'chartData', '[]'::jsonb,
      'rankedTraders', '[]'::jsonb,
      'profiles', '{}'::jsonb,
      'yourRank', null,
      'todayStats', jsonb_build_object(
        'yourTradeCount', 0,
        'yourAvgPnl', 0,
        'yourAvgRR', null,
        'globalAvgPnl', 0,
        'globalAvgRR', null,
        'globalTradeCount', 0,
        'percentileTopPct', case when p_viewer_id is null then '—' else '0.0' end
      )
    )
    else jsonb_build_object(
      'hasData', true,
      'chartData', coalesce((
        select jsonb_agg(jsonb_build_object(
          'bucketId', c.ny_day::text,
          'label', extract(month from c.ny_day)::int::text || '/' ||
            extract(day from c.ny_day)::int::text || '/' ||
            extract(year from c.ny_day)::int::text,
          'sortKey', extract(year from c.ny_day)::int * 10000
            + extract(month from c.ny_day)::int * 100
            + extract(day from c.ny_day)::int,
          'average', c.average,
          'best', c.best,
          'worst', c.worst,
          'you', c.you,
          'contributorCount', c.contributor_count
        ) order by c.ny_day)
        from chart_days c
      ), '[]'::jsonb),
      'rankedTraders', coalesce((
        select jsonb_agg(jsonb_build_object(
          'rank', r.rank,
          'userId', r.user_id,
          'totalPnl', r.total_pnl,
          'tradeCount', r.trade_count,
          'avgRR', r.avg_rr
        ) order by r.rank)
        from top_rows r
      ), '[]'::jsonb),
      'profiles', coalesce((
        select jsonb_object_agg(pr.id::text, jsonb_build_object(
          'id', pr.id,
          'username', pr.username,
          'name', pr.name,
          'avatar_url', pr.avatar_url
        ))
        from public.profiles pr
        where pr.id in (select user_id from top_rows)
      ), '{}'::jsonb),
      'yourRank', (
        select jsonb_build_object(
          'rank', r.rank,
          'totalTraders', r.total_traders,
          'percentileTopPct', to_char(round((r.rank::numeric / r.total_traders) * 100, 1), 'FM999990.0'),
          'totalPnl', r.total_pnl,
          'tradeCount', r.trade_count
        )
        from ranked r
        where r.user_id = p_viewer_id
      ),
      'todayStats', jsonb_build_object(
        'yourTradeCount', coalesce((select trade_count from yours), 0),
        'yourAvgPnl', case
          when coalesce((select trade_count from yours), 0) > 0
            then (select pnl_sum from yours) / (select trade_count from yours)
          else 0
        end,
        'yourAvgRR', (select avg_rr from yours),
        'globalAvgPnl', (select pnl_sum from totals) / (select trade_count from totals),
        'globalAvgRR', (select avg_rr from totals),
        'globalTradeCount', (select trade_count from totals),
        'percentileTopPct', case
          when p_viewer_id is null then '—'
          when (select peer_count from peers) = 0 then
            case when coalesce((select trade_count from yours), 0) > 0 then '100.0' else '0.0' end
          else to_char(
            round(least(100, greatest(0,
              ((select beaten from peers)::numeric / (select peer_count from peers)) * 100
            )), 1),
            'FM999990.0'
          )
        end
      )
    )
  end;
$$;

create or replace function public.leaderboard_ranked_window(
  p_view text,
  p_account_type text default 'all',
  p_now timestamptz default now(),
  p_custom_start timestamptz default null,
  p_custom_end timestamptz default null,
  p_custom_start_ymd date default null,
  p_custom_end_ymd date default null,
  p_viewer_id uuid default null,
  p_rank_limit int default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_requested text := case
    when p_view in ('7D', '30D', '90D', 'YTD', 'ALL', 'Custom') then p_view
    else '7D'
  end;
  v_candidates text[];
  v_view text;
  v_payload jsonb;
  v_index int;
begin
  if v_requested = 'Custom' then
    v_candidates := array['Custom', '7D', '30D', '90D', 'YTD', 'ALL'];
  elsif v_requested = '7D' then
    v_candidates := array['7D', '30D', '90D', 'YTD', 'ALL'];
  elsif v_requested = '30D' then
    v_candidates := array['30D', '90D', 'YTD', 'ALL'];
  elsif v_requested = '90D' then
    v_candidates := array['90D', 'YTD', 'ALL'];
  elsif v_requested = 'YTD' then
    v_candidates := array['YTD', 'ALL'];
  else
    v_candidates := array['ALL'];
  end if;

  for v_index in 1 .. coalesce(array_length(v_candidates, 1), 0) loop
    v_view := v_candidates[v_index];
    v_payload := public.leaderboard_ranked_window_one(
      v_view,
      p_account_type,
      p_now,
      p_custom_start,
      p_custom_end,
      p_custom_start_ymd,
      p_custom_end_ymd,
      p_viewer_id,
      p_rank_limit
    );
    if coalesce((v_payload->>'hasData')::boolean, false) then
      return v_payload || jsonb_build_object(
        'requestedView', v_requested,
        'effectiveView', v_view,
        'usedFallback', v_view is distinct from v_requested
      );
    end if;
  end loop;

  return coalesce(v_payload, '{}'::jsonb) || jsonb_build_object(
    'requestedView', v_requested,
    'effectiveView', v_requested,
    'usedFallback', false,
    'hasData', false
  );
end;
$$;

comment on function public.leaderboard_ranked_window(
  text, text, timestamptz, timestamptz, timestamptz, date, date, uuid, int
) is
  'Ranked leaderboard window and daily chart buckets. Public trades of non-private profiles only. Does not return raw trades.';

revoke all on function public.leaderboard_ranked_window_one(
  text, text, timestamptz, timestamptz, timestamptz, date, date, uuid, int
) from public;
revoke all on function public.leaderboard_ranked_window(
  text, text, timestamptz, timestamptz, timestamptz, date, date, uuid, int
) from public;

grant execute on function public.leaderboard_ranked_window(
  text, text, timestamptz, timestamptz, timestamptz, date, date, uuid, int
) to anon, authenticated, service_role;
