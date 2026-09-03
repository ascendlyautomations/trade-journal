-- Psychology report AI summary cache (owner-only) + check-in history bootstrap RPC.

create table if not exists public.psychology_report_ai_cache (
  user_id uuid not null references public.profiles (id) on delete cascade,
  report_id text not null,
  facts_hash text not null,
  ai_summary text not null,
  generated_at timestamptz not null default now(),
  primary key (user_id, report_id)
);

comment on table public.psychology_report_ai_cache is
  'Owner-only cached AI psychology report summaries keyed by report period + facts hash.';

alter table public.psychology_report_ai_cache enable row level security;

drop policy if exists psychology_report_ai_cache_select_own on public.psychology_report_ai_cache;
create policy psychology_report_ai_cache_select_own
  on public.psychology_report_ai_cache
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists psychology_report_ai_cache_insert_own on public.psychology_report_ai_cache;
create policy psychology_report_ai_cache_insert_own
  on public.psychology_report_ai_cache
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists psychology_report_ai_cache_update_own on public.psychology_report_ai_cache;
create policy psychology_report_ai_cache_update_own
  on public.psychology_report_ai_cache
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists psychology_report_ai_cache_delete_own on public.psychology_report_ai_cache;
create policy psychology_report_ai_cache_delete_own
  on public.psychology_report_ai_cache
  for delete to authenticated
  using (user_id = auth.uid());

-- Efficient check-in history bootstrap: one query for check-ins + per-day trade aggregates.
create or replace function public.rpc_v1_check_in_history_bootstrap(
  p_start_date date,
  p_end_date date,
  p_account_id uuid default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_check_ins jsonb;
  v_day_stats jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', ci.id,
        'user_id', ci.user_id,
        'check_in_date', ci.check_in_date,
        'sleep_hours', ci.sleep_hours,
        'sleep_quality', ci.sleep_quality,
        'morning_rating', ci.morning_rating,
        'stress_level', ci.stress_level,
        'energy_level', ci.energy_level,
        'focus_level', ci.focus_level,
        'notes', ci.notes,
        'created_at', to_char(ci.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'updated_at', to_char(ci.updated_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      )
      order by ci.check_in_date desc
    ),
    '[]'::jsonb
  )
  into v_check_ins
  from public.trader_daily_check_ins ci
  where ci.user_id = v_uid
    and ci.check_in_date between p_start_date and p_end_date;

  with scoped_trades as (
    select
      coalesce(
        nullif(trim(t.trade_date), '')::date,
        nullif(trim(t.date), '')::date
      ) as trade_day,
      t.pnl
    from public.trades t
    where t.user_id = v_uid
      and (p_account_id is null or t.account_id = p_account_id::text)
      and coalesce(nullif(trim(t.trade_date), ''), nullif(trim(t.date), '')) is not null
  ),
  daily as (
    select
      trade_day,
      count(*)::int as trade_count,
      coalesce(sum(pnl), 0)::numeric as total_pnl,
      count(*) filter (where pnl > 0)::int as win_count,
      count(*) filter (where pnl < 0)::int as loss_count
    from scoped_trades
    where trade_day between p_start_date and p_end_date
    group by trade_day
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'check_in_date', to_char(trade_day, 'YYYY-MM-DD'),
        'trade_count', trade_count,
        'total_pnl', total_pnl,
        'win_count', win_count,
        'loss_count', loss_count
      )
      order by trade_day desc
    ),
    '[]'::jsonb
  )
  into v_day_stats
  from daily;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid::text
    ),
    'data', jsonb_build_object(
      'check_ins', coalesce(v_check_ins, '[]'::jsonb),
      'day_stats', coalesce(v_day_stats, '[]'::jsonb)
    )
  );
end;
$$;

comment on function public.rpc_v1_check_in_history_bootstrap(date, date, uuid) is
  'Owner-only check-in history window with per-day trade aggregates — no N+1.';

revoke all on function public.rpc_v1_check_in_history_bootstrap(date, date, uuid) from public;
grant execute on function public.rpc_v1_check_in_history_bootstrap(date, date, uuid) to authenticated;
