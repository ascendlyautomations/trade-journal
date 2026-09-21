-- Phase 2 — analytical foundation hardening (no production UI cutover).

drop function if exists public.analytics_calendar_day(text, text, timestamptz);
drop function if exists public.analytics_legacy_trading_day_key(text, text, timestamptz);
drop function if exists public.analytics_realized_sort_ts(text, text, timestamptz);

-- ---------------------------------------------------------------------------
-- Timestamp parsing (+00 short offset, fractional seconds, space/T, UTC fallback)
-- ---------------------------------------------------------------------------

create or replace function public.analytics_parse_trade_timestamp(p_raw text)
returns timestamptz
language plpgsql
immutable
set search_path = public
as $$
declare
  v text := nullif(trim(coalesce(p_raw, '')), '');
begin
  if v is null then
    return null;
  end if;

  if v ~* 'Z$' then
    return v::timestamptz;
  end if;

  -- ISO offset with minutes (+00:00, -04:00) or compact (+0000, -0400)
  if v ~ '[+-]\d{2}:\d{2}(:?\d{2})?$' or v ~ '[+-]\d{4}$' then
    return v::timestamptz;
  end if;

  -- Short hour-only offset stored by imports (+00, -05) — normalize to +00:00
  if v ~ '[+-]\d{2}$' then
    v := replace(v, ' ', 'T');
    return (v || ':00')::timestamptz;
  end if;

  -- Timezone-less wall strings — treat as UTC storage (matches web normalizeStoredUtcTimestamp)
  v := replace(v, ' ', 'T');
  return (v || 'Z')::timestamptz;
exception
  when others then
    return null;
end;
$$;

comment on function public.analytics_parse_trade_timestamp(text) is
  'Parse trade entry/exit text to timestamptz: Z, offsets (+00:00, +00, +0000), or timezone-less UTC.';

-- trades.created_at is timestamp without time zone — interpret as UTC (Supabase/API convention).
create or replace function public.analytics_trade_created_at_utc(p_created_at timestamp)
returns timestamptz
language sql
immutable
set search_path = public
as $$
  select case
    when p_created_at is null then null
    else p_created_at at time zone 'UTC'
  end;
$$;

comment on function public.analytics_trade_created_at_utc(timestamp) is
  'Normalize trades.created_at (timestamp without tz) as UTC instant for analytics fallbacks.';

create or replace function public.analytics_trade_sort_instant(
  p_entry_time text,
  p_exit_time text,
  p_created_at timestamp
)
returns timestamptz
language sql
immutable
set search_path = public
as $$
  select coalesce(
    public.analytics_parse_trade_timestamp(p_entry_time),
    public.analytics_parse_trade_timestamp(p_exit_time),
    public.analytics_trade_created_at_utc(p_created_at)
  );
$$;

create or replace function public.analytics_calendar_day(
  p_entry_time text,
  p_exit_time text,
  p_created_at timestamp
)
returns date
language sql
immutable
set search_path = public
as $$
  select case
    when public.analytics_trade_sort_instant(p_entry_time, p_exit_time, p_created_at) is null then null
    else (
      public.analytics_trade_sort_instant(p_entry_time, p_exit_time, p_created_at)
      at time zone 'America/New_York'
    )::date
  end;
$$;

create or replace function public.analytics_legacy_trading_day_key(
  p_entry_time text,
  p_exit_time text,
  p_created_at timestamp
)
returns date
language plpgsql
immutable
set search_path = public
as $$
declare
  v_instant timestamptz := public.analytics_trade_sort_instant(
    p_entry_time, p_exit_time, p_created_at
  );
  v_local timestamp;
  v_hour int;
begin
  if v_instant is null then
    return null;
  end if;
  v_local := v_instant at time zone 'America/New_York';
  v_hour := extract(hour from v_local)::int;
  if v_hour >= 18 then
    v_local := (v_local::date + 1)::timestamp;
  end if;
  return v_local::date;
end;
$$;

create or replace function public.analytics_realized_sort_ts(
  p_entry_time text,
  p_exit_time text,
  p_created_at timestamp
)
returns timestamptz
language sql
immutable
set search_path = public
as $$
  select coalesce(
    public.analytics_parse_trade_timestamp(p_exit_time),
    public.analytics_parse_trade_timestamp(p_entry_time),
    public.analytics_trade_created_at_utc(p_created_at)
  );
$$;

-- ---------------------------------------------------------------------------
-- Revision: bump only when aggregate-affecting trade columns change
-- ---------------------------------------------------------------------------

create or replace function public.analytics_trade_row_affects_stats(
  p_old public.trades,
  p_new public.trades
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select
    p_old.user_id is distinct from p_new.user_id
    or p_old.account_id is distinct from p_new.account_id
    or p_old.account_type is distinct from p_new.account_type
    or p_old.mode is distinct from p_new.mode
    or p_old.trade_mode is distinct from p_new.trade_mode
    or p_old.pnl is distinct from p_new.pnl
    or p_old.direction is distinct from p_new.direction
    or p_old.rr is distinct from p_new.rr
    or p_old.duration_seconds is distinct from p_new.duration_seconds
    or p_old.entry_time is distinct from p_new.entry_time
    or p_old.exit_time is distinct from p_new.exit_time
    or p_old.created_at is distinct from p_new.created_at;
$$;

create or replace function public.trades_maintain_trade_daily_stats()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_bump boolean := false;
begin
  if tg_op = 'INSERT' then
    perform public.analytics_sync_trade_daily_stats_from_row(new, 1);
    v_user_id := new.user_id;
    v_bump := new.user_id is not null;
  elsif tg_op = 'DELETE' then
    perform public.analytics_sync_trade_daily_stats_from_row(old, -1);
    v_user_id := old.user_id;
    v_bump := old.user_id is not null;
  elsif tg_op = 'UPDATE' then
    if not public.analytics_trade_row_affects_stats(old, new) then
      return new;
    end if;
    perform public.analytics_sync_trade_daily_stats_from_row(old, -1);
    perform public.analytics_sync_trade_daily_stats_from_row(new, 1);
    v_user_id := coalesce(new.user_id, old.user_id);
    v_bump := v_user_id is not null;
  end if;

  if v_bump then
    perform public.analytics_bump_user_revision(v_user_id);
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Service-role parity corpus helper (shadow validation)
-- ---------------------------------------------------------------------------

create or replace function public.analytics_parity_user_range(
  p_user_id uuid,
  p_start date,
  p_end date,
  p_account_id uuid default null,
  p_mode text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_raw jsonb;
  v_agg jsonb;
  v_parity jsonb;
begin
  v_raw := public.analytics_raw_normal_range_metrics(
    p_user_id, p_start, p_end, p_account_id, p_mode
  );

  select jsonb_build_object(
    'trade_count', coalesce(sum(trade_count), 0),
    'win_count', coalesce(sum(win_count), 0),
    'loss_count', coalesce(sum(loss_count), 0),
    'breakeven_count', coalesce(sum(breakeven_count), 0),
    'net_pnl', coalesce(sum(net_pnl), 0),
    'gross_profit', coalesce(sum(gross_profit), 0),
    'gross_loss', coalesce(sum(gross_loss), 0),
    'long_count', coalesce(sum(long_count), 0),
    'long_pnl', coalesce(sum(long_pnl), 0),
    'short_count', coalesce(sum(short_count), 0),
    'short_pnl', coalesce(sum(short_pnl), 0),
    'sum_rr', coalesce(sum(sum_rr), 0),
    'rr_count', coalesce(sum(rr_count), 0),
    'sum_hold_seconds', coalesce(sum(sum_hold_seconds), 0),
    'hold_count', coalesce(sum(hold_count), 0),
    'largest_win', max(largest_win),
    'largest_loss', min(largest_loss)
  )
  into v_agg
  from public.trade_daily_stats s
  where s.user_id = p_user_id
    and s.calendar_day between p_start and p_end
    and (p_account_id is null or s.account_id is not distinct from p_account_id)
    and (
      nullif(lower(trim(coalesce(p_mode, ''))), '') is null
      or s.mode_effective = lower(trim(p_mode))
    )
    and (
      nullif(lower(trim(coalesce(p_mode, ''))), '') is not null
      or s.mode_effective <> 'backtest'
    );

  v_parity := jsonb_build_object(
    'trade_count', (v_agg->>'trade_count')::numeric = (v_raw->>'trade_count')::numeric,
    'win_count', (v_agg->>'win_count')::numeric = (v_raw->>'win_count')::numeric,
    'loss_count', (v_agg->>'loss_count')::numeric = (v_raw->>'loss_count')::numeric,
    'breakeven_count', (v_agg->>'breakeven_count')::numeric = (v_raw->>'breakeven_count')::numeric,
    'net_pnl', public.analytics_numeric_near((v_agg->>'net_pnl')::numeric, (v_raw->>'net_pnl')::numeric),
    'gross_profit', public.analytics_numeric_near((v_agg->>'gross_profit')::numeric, (v_raw->>'gross_profit')::numeric),
    'gross_loss', public.analytics_numeric_near((v_agg->>'gross_loss')::numeric, (v_raw->>'gross_loss')::numeric),
    'long_count', (v_agg->>'long_count')::numeric = (v_raw->>'long_count')::numeric,
    'long_pnl', public.analytics_numeric_near((v_agg->>'long_pnl')::numeric, (v_raw->>'long_pnl')::numeric),
    'short_count', (v_agg->>'short_count')::numeric = (v_raw->>'short_count')::numeric,
    'short_pnl', public.analytics_numeric_near((v_agg->>'short_pnl')::numeric, (v_raw->>'short_pnl')::numeric),
    'sum_rr', public.analytics_numeric_near((v_agg->>'sum_rr')::numeric, (v_raw->>'sum_rr')::numeric),
    'rr_count', (v_agg->>'rr_count')::numeric = (v_raw->>'rr_count')::numeric,
    'sum_hold_seconds', (v_agg->>'sum_hold_seconds')::bigint = (v_raw->>'sum_hold_seconds')::bigint,
    'hold_count', (v_agg->>'hold_count')::numeric = (v_raw->>'hold_count')::numeric,
    'largest_win', public.analytics_numeric_near((v_agg->>'largest_win')::numeric, (v_raw->>'largest_win')::numeric, 0.0001)
      or ((v_agg->>'largest_win') is null and (v_raw->>'largest_win') is null),
    'largest_loss', public.analytics_numeric_near((v_agg->>'largest_loss')::numeric, (v_raw->>'largest_loss')::numeric, 0.0001)
      or ((v_agg->>'largest_loss') is null and (v_raw->>'largest_loss') is null)
  );

  return jsonb_build_object(
    'user_id', p_user_id,
    'start', p_start,
    'end', p_end,
    'account_id', p_account_id,
    'mode', p_mode,
    'aggregate', v_agg,
    'raw_normal', v_raw,
    'parity', v_parity,
    'parity_all_additive', (
      select bool_and(value::boolean)
      from jsonb_each_text(v_parity) as t(key, value)
    )
  );
end;
$$;

revoke all on function public.analytics_parity_user_range(uuid, date, date, uuid, text) from public, anon, authenticated;
grant execute on function public.analytics_parity_user_range(uuid, date, date, uuid, text) to service_role;

create or replace function public.rebuild_trade_daily_stats_all_users()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_n integer := 0;
begin
  for v_uid in
    select distinct t.user_id
    from public.trades t
    where t.user_id is not null
  loop
    perform public.rebuild_trade_daily_stats_for_user(v_uid);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

revoke all on function public.rebuild_trade_daily_stats_all_users() from public, anon, authenticated;
grant execute on function public.rebuild_trade_daily_stats_all_users() to service_role;

-- Rebuild after parser/created_at semantics change (idempotent on re-apply).
do $migrate$
begin
  perform public.rebuild_trade_daily_stats_all_users();
exception
  when undefined_function then
    null;
end;
$migrate$;
