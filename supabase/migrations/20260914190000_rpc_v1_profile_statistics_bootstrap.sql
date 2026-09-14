-- Profile Statistics bootstrap — server-side parity with iOS ProfileStatisticsMetrics.compute

create or replace function public.profile_statistics_resolve_account_mode(
  p_account_mode text,
  p_account_type text,
  p_trade_mode text
)
returns text
language sql
immutable
as $$
  select case lower(trim(coalesce(
    nullif(trim(coalesce(p_account_mode, '')), ''),
    nullif(trim(coalesce(p_account_type, '')), ''),
    nullif(trim(coalesce(p_trade_mode, '')), ''),
    ''
  )))
    when 'eval' then 'evaluation'
    when 'evaluation' then 'evaluation'
    when 'funded' then 'funded'
    when 'sim' then 'sim'
    when 'replay' then 'sim'
    when 'backtest' then 'backtest'
    when 'live' then 'live'
    else null
  end;
$$;

create or replace function public.rpc_v1_profile_statistics_bootstrap(
  p_profile_id uuid
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_viewer uuid := auth.uid();
  v_can_view boolean := false;
  v_modes jsonb := '{}'::jsonb;
  v_mode text;
  v_mode_list text[] := array['all', 'eval', 'funded', 'live', 'sim', 'backtest'];
  v_total integer := 0;
  v_wins integer := 0;
  v_loss_count integer := 0;
  v_long_trades integer := 0;
  v_total_pnl numeric := 0;
  v_gross_wins numeric := 0;
  v_gross_losses numeric := 0;
  v_biggest_win numeric := 0;
  v_biggest_loss numeric := null;
  v_win_rate numeric := null;
  v_profit_factor numeric := null;
  v_average_winner numeric := null;
  v_average_loser numeric := null;
  v_profit_per_trade numeric := null;
  v_current_equity numeric := 0;
  v_equity jsonb := '[]'::jsonb;
  v_running numeric := 0;
  v_idx integer := 0;
  v_max_win_streak integer := 0;
  v_max_loss_streak integer := 0;
  v_cur_win integer := 0;
  v_cur_loss integer := 0;
  v_pnl numeric;
  v_session_total integer := 0;
  v_session_rows jsonb := '[]'::jsonb;
  v_ny integer := 0;
  v_london integer := 0;
  v_asia integer := 0;
  rec record;
  v_raw text;
  v_label text;
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
      'meta', jsonb_build_object(
        'contract_version', 'v1',
        'found', false,
        'server_time', to_jsonb(timezone('utc', now())),
        'viewer_id', v_viewer
      ),
      'data', jsonb_build_object('modes', '{}'::jsonb)
    );
  end if;

  create temp table _profile_stats_base (
    pnl numeric,
    created_at timestamptz,
    trade_id uuid,
    is_long boolean,
    session_raw text,
    acct_mode text
  ) on commit drop;

  insert into _profile_stats_base (pnl, created_at, trade_id, is_long, session_raw, acct_mode)
  select
    t.pnl,
    t.created_at,
    t.id,
    (lower(coalesce(t.direction, '')) = 'long'),
    coalesce(t.session, ''),
    public.profile_statistics_resolve_account_mode(a.mode, t.account_type, t.mode)
  from public.trades t
  left join public.accounts a
    on a.id = t.account_id and a.user_id = t.user_id
  where t.user_id = p_profile_id
    and coalesce(t.is_public, false) = true;

  foreach v_mode in array v_mode_list loop
    v_total := 0;
    v_wins := 0;
    v_loss_count := 0;
    v_long_trades := 0;
    v_total_pnl := 0;
    v_gross_wins := 0;
    v_gross_losses := 0;
    v_biggest_win := 0;
    v_biggest_loss := null;
    v_win_rate := null;
    v_profit_factor := null;
    v_average_winner := null;
    v_average_loser := null;
    v_profit_per_trade := null;
    v_current_equity := 0;
    v_equity := '[]'::jsonb;
    v_running := 0;
    v_idx := 0;
    v_max_win_streak := 0;
    v_max_loss_streak := 0;
    v_cur_win := 0;
    v_cur_loss := 0;
    v_ny := 0;
    v_london := 0;
    v_asia := 0;

    select
      count(*)::integer,
      count(*) filter (where coalesce(pnl, 0) > 0)::integer,
      count(*) filter (where coalesce(pnl, 0) < 0)::integer,
      count(*) filter (where is_long)::integer,
      coalesce(sum(coalesce(pnl, 0)), 0),
      coalesce(sum(pnl) filter (where coalesce(pnl, 0) > 0), 0),
      coalesce(sum(pnl) filter (where coalesce(pnl, 0) < 0), 0),
      coalesce(max(pnl), 0),
      min(pnl) filter (where coalesce(pnl, 0) < 0)
    into
      v_total, v_wins, v_loss_count, v_long_trades,
      v_total_pnl, v_gross_wins, v_gross_losses,
      v_biggest_win, v_biggest_loss
    from _profile_stats_base b
    where (
        v_mode = 'all'
        or (v_mode = 'eval' and b.acct_mode = 'evaluation')
        or (v_mode = 'funded' and b.acct_mode = 'funded')
        or (v_mode = 'live' and b.acct_mode = 'live')
        or (v_mode = 'sim' and b.acct_mode = 'sim')
        or (v_mode = 'backtest' and b.acct_mode = 'backtest')
      )
      and (v_mode = 'backtest' or coalesce(b.acct_mode, '') <> 'backtest');

    if v_total > 0 then
      v_win_rate := round(v_wins::numeric / v_total::numeric, 8);
      v_profit_per_trade := round(v_total_pnl / v_total::numeric, 8);
    end if;
    if v_gross_losses < 0 then
      v_profit_factor := round(v_gross_wins / abs(v_gross_losses), 8);
    end if;
    if v_wins > 0 then
      v_average_winner := round(v_gross_wins / v_wins::numeric, 8);
    end if;
    if v_loss_count > 0 then
      v_average_loser := round(v_gross_losses / v_loss_count::numeric, 8);
    end if;

    for rec in
      select b.pnl, b.created_at, b.trade_id
      from _profile_stats_base b
      where (
          v_mode = 'all'
          or (v_mode = 'eval' and b.acct_mode = 'evaluation')
          or (v_mode = 'funded' and b.acct_mode = 'funded')
          or (v_mode = 'live' and b.acct_mode = 'live')
          or (v_mode = 'sim' and b.acct_mode = 'sim')
          or (v_mode = 'backtest' and b.acct_mode = 'backtest')
        )
        and (v_mode = 'backtest' or coalesce(b.acct_mode, '') <> 'backtest')
      order by b.created_at asc, b.trade_id asc
    loop
      v_running := v_running + coalesce(rec.pnl, 0);
      v_equity := v_equity || jsonb_build_array(
        jsonb_build_object(
          'index', v_idx,
          'equity', v_running,
          'date', to_jsonb(rec.created_at)
        )
      );
      v_idx := v_idx + 1;
      v_current_equity := v_running;

      v_pnl := coalesce(rec.pnl, 0);
      if v_pnl > 0 then
        v_cur_win := v_cur_win + 1;
        v_cur_loss := 0;
      elsif v_pnl < 0 then
        v_cur_loss := v_cur_loss + 1;
        v_cur_win := 0;
      else
        v_cur_win := 0;
        v_cur_loss := 0;
      end if;
      if v_cur_win > v_max_win_streak then v_max_win_streak := v_cur_win; end if;
      if v_cur_loss > v_max_loss_streak then v_max_loss_streak := v_cur_loss; end if;
    end loop;

    for rec in
      select b.session_raw
      from _profile_stats_base b
      where (
          v_mode = 'all'
          or (v_mode = 'eval' and b.acct_mode = 'evaluation')
          or (v_mode = 'funded' and b.acct_mode = 'funded')
          or (v_mode = 'live' and b.acct_mode = 'live')
          or (v_mode = 'sim' and b.acct_mode = 'sim')
          or (v_mode = 'backtest' and b.acct_mode = 'backtest')
        )
        and (v_mode = 'backtest' or coalesce(b.acct_mode, '') <> 'backtest')
    loop
      v_raw := lower(trim(coalesce(rec.session_raw, '')));
      v_label := null;
      if v_raw like '%ny%' or v_raw like '%new york%' then
        v_label := 'NY';
      elsif v_raw like '%london%' or v_raw like '%ldn%' or v_raw like '%uk%' then
        v_label := 'London';
      elsif v_raw like '%asia%' or v_raw like '%asian%' or v_raw like '%tokyo%' then
        v_label := 'Asia';
      end if;
      if v_label = 'NY' then v_ny := v_ny + 1;
      elsif v_label = 'London' then v_london := v_london + 1;
      elsif v_label = 'Asia' then v_asia := v_asia + 1;
      end if;
    end loop;

    v_session_total := v_ny + v_london + v_asia;
    v_session_rows := '[]'::jsonb;
    if v_ny > 0 then
      v_session_rows := v_session_rows || jsonb_build_array(jsonb_build_object(
        'label', 'NY', 'count', v_ny,
        'pct', case when v_session_total > 0 then (v_ny::float / v_session_total::float) * 100 else 0 end
      ));
    end if;
    if v_london > 0 then
      v_session_rows := v_session_rows || jsonb_build_array(jsonb_build_object(
        'label', 'London', 'count', v_london,
        'pct', case when v_session_total > 0 then (v_london::float / v_session_total::float) * 100 else 0 end
      ));
    end if;
    if v_asia > 0 then
      v_session_rows := v_session_rows || jsonb_build_array(jsonb_build_object(
        'label', 'Asia', 'count', v_asia,
        'pct', case when v_session_total > 0 then (v_asia::float / v_session_total::float) * 100 else 0 end
      ));
    end if;

    v_modes := v_modes || jsonb_build_object(
      v_mode,
      jsonb_build_object(
        'filtered_trade_count', v_total,
        'win_rate', v_win_rate,
        'profit_factor', v_profit_factor,
        'average_winner', v_average_winner,
        'average_loser', v_average_loser,
        'profit_per_trade', v_profit_per_trade,
        'biggest_win', v_biggest_win,
        'biggest_loss', v_biggest_loss,
        'long_trades', v_long_trades,
        'max_win_streak', v_max_win_streak,
        'max_loss_streak', v_max_loss_streak,
        'session_total', v_session_total,
        'session_breakdown', v_session_rows,
        'current_equity', v_current_equity,
        'equity_data', v_equity
      )
    );
  end loop;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'found', true,
      'server_time', to_jsonb(timezone('utc', now())),
      'viewer_id', v_viewer
    ),
    'data', jsonb_build_object(
      'profile_id', p_profile_id,
      'modes', v_modes
    )
  );
end;
$$;

comment on function public.rpc_v1_profile_statistics_bootstrap(uuid) is
  'Profile Statistics tab aggregates — parity with native ProfileStatisticsMetrics (all filter modes).';

revoke all on function public.rpc_v1_profile_statistics_bootstrap(uuid) from public;
grant execute on function public.rpc_v1_profile_statistics_bootstrap(uuid) to authenticated;
grant execute on function public.rpc_v1_profile_statistics_bootstrap(uuid) to anon;
