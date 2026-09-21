-- Phase 8G — Owner trade detail comparison: remove TEMP TABLE (Supabase pooler-safe) + meta wire fix.

create or replace function public.owner_comparison_scope_trades(p_viewer uuid)
returns table (
  id uuid,
  pnl numeric,
  rr numeric,
  hold_seconds integer,
  root_ticker text,
  activity_at timestamptz
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select distinct on (t.id)
    t.id,
    coalesce(t.pnl, 0) as pnl,
    t.rr,
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
    ) as activity_at
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

-- Profile tab V1: pagination cursor from v_items JSON (CTE scope safe).
create or replace function public.rpc_v1_profile_tab_trades(
  p_profile_id uuid,
  p_limit integer default 24,
  p_cursor text default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_viewer uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 24), 1), 100);
  v_cursor_ts timestamptz;
  v_cursor_id uuid;
  v_can_view boolean := false;
  v_items jsonb := '[]'::jsonb;
  v_has_more boolean := false;
  v_next_cursor text := null;
  v_engagement jsonb := '{}'::jsonb;
begin
  if p_profile_id is null then
    raise exception 'invalid_profile_id' using errcode = '22023';
  end if;

  select (
    v_viewer = p_profile_id
    or coalesce(p.is_private, false) = false
    or exists (
      select 1 from public.followers f
      where f.follower_id = v_viewer and f.following_id = p_profile_id
    )
  ) into v_can_view
  from public.profiles p
  where p.id = p_profile_id;

  if not coalesce(v_can_view, false) then
    return jsonb_build_object(
      'meta', jsonb_build_object('contract_version', 'v1', 'found', false),
      'data', jsonb_build_object(
        'tab', 'trades',
        'items', '[]'::jsonb,
        'engagement', '{}'::jsonb,
        'next_cursor', null
      )
    );
  end if;

  if p_cursor is not null and trim(p_cursor) <> '' then
    v_cursor_ts := split_part(p_cursor, '|', 1)::timestamptz;
    v_cursor_id := split_part(p_cursor, '|', 2)::uuid;
  end if;

  with page as (
    select t.*
    from public.trades t
    where t.user_id = p_profile_id
      and t.is_public is true
      and (
        v_cursor_ts is null
        or (t.created_at, t.id) < (v_cursor_ts, v_cursor_id)
      )
    order by t.created_at desc, t.id desc
    limit v_limit + 1
  ),
  trimmed as (
    select * from page limit v_limit
  )
  select
    coalesce(jsonb_agg(to_jsonb(tr) order by tr.created_at desc, tr.id desc), '[]'::jsonb),
    (select count(*) > v_limit from page)
  into v_items, v_has_more
  from trimmed tr;

  if v_has_more then
    select (elem->>'created_at') || '|' || (elem->>'id')
    into v_next_cursor
    from (
      select elem
      from jsonb_array_elements(v_items) as elem
      order by (elem->>'created_at') asc, (elem->>'id') asc
      limit 1
    ) sub;
  end if;

  with trade_ids as (
    select (elem->>'id')::uuid as id
    from jsonb_array_elements(v_items) elem
    where elem ? 'id'
  )
  select coalesce(jsonb_object_agg(
    ti.id::text,
    jsonb_build_object(
      'like_count', coalesce(lc.like_count, 0),
      'liked_by_me', coalesce(lc.liked_by_me, false),
      'comment_count', coalesce(cc.comment_count, 0)
    )
  ), '{}'::jsonb)
  into v_engagement
  from trade_ids ti
  left join lateral (
    select count(*)::integer as like_count,
      bool_or(v_viewer is not null and tl.user_id = v_viewer) as liked_by_me
    from public.trade_likes tl where tl.trade_id = ti.id
  ) lc on true
  left join lateral (
    select count(*)::integer as comment_count
    from public.trade_comments tc where tc.trade_id = ti.id
  ) cc on true;

  return jsonb_build_object(
    'meta', jsonb_build_object('contract_version', 'v1', 'found', true),
    'data', jsonb_build_object(
      'tab', 'trades',
      'items', v_items,
      'engagement', v_engagement,
      'next_cursor', v_next_cursor
    )
  );
end;
$$;

revoke all on function public.owner_comparison_scope_trades(uuid) from public;
grant execute on function public.owner_comparison_scope_trades(uuid) to authenticated;
