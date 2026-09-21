-- Phase 1B — Analytical foundation (shadow mode only).
-- Normal TradeTraxs calendar day is NOT the 18:00 ET prop-firm/session trading day.
-- Production Calendar/Dashboard/Profile/Reports remain on legacy paths until later phases.

-- ---------------------------------------------------------------------------
-- A. Normal analytics calendar day (America/New_York civil date, no 18:00 roll)
-- ---------------------------------------------------------------------------
-- Timestamp priority (journal / execution semantics):
--   1) entry_time (parsed)
--   2) exit_time (parsed)
--   3) created_at
-- Overnight: a single trade stays on the civil date of that instant in ET (entry wins).
-- NULL: if no parseable instant, trade is excluded from trade_daily_stats.
-- Does NOT read or rewrite trades.trade_date (legacy journal field).

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
  if v ~ '[+-]\d{2}:\d{2}(:?\d{2})?$' or v ~ '[+-]\d{4}$' then
    return v::timestamptz;
  end if;
  v := replace(v, ' ', 'T');
  return (v || 'Z')::timestamptz;
exception
  when others then
    return null;
end;
$$;

create or replace function public.analytics_calendar_day(
  p_entry_time text,
  p_exit_time text,
  p_created_at timestamptz
)
returns date
language sql
immutable
set search_path = public
as $$
  select case
    when coalesce(
      public.analytics_parse_trade_timestamp(p_entry_time),
      public.analytics_parse_trade_timestamp(p_exit_time),
      p_created_at
    ) is null then null
    else (
      coalesce(
        public.analytics_parse_trade_timestamp(p_entry_time),
        public.analytics_parse_trade_timestamp(p_exit_time),
        p_created_at
      ) at time zone 'America/New_York'
    )::date
  end;
$$;

comment on function public.analytics_calendar_day(text, text, timestamptz) is
  'Normal TradeTraxs analytics/calendar day: ET civil date from entry_time → exit_time → created_at. No 18:00 session rollover.';

-- ---------------------------------------------------------------------------
-- B. Legacy prop-firm / futures session day (shadow comparison ONLY)
-- ---------------------------------------------------------------------------

create or replace function public.analytics_legacy_trading_day_key(
  p_entry_time text,
  p_exit_time text,
  p_created_at timestamptz
)
returns date
language plpgsql
immutable
set search_path = public
as $$
declare
  v_instant timestamptz := coalesce(
    public.analytics_parse_trade_timestamp(p_entry_time),
    public.analytics_parse_trade_timestamp(p_exit_time),
    p_created_at
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

comment on function public.analytics_legacy_trading_day_key(text, text, timestamptz) is
  'Legacy 18:00 America/New_York trading-day key (Calendar/prop-firm). NOT used for trade_daily_stats.calendar_day.';

-- ---------------------------------------------------------------------------
-- Realized chronological sort instant (equity curve / streaks — not calendar)
-- ---------------------------------------------------------------------------

create or replace function public.analytics_realized_sort_ts(
  p_entry_time text,
  p_exit_time text,
  p_created_at timestamptz
)
returns timestamptz
language sql
immutable
set search_path = public
as $$
  select coalesce(
    public.analytics_parse_trade_timestamp(p_exit_time),
    public.analytics_parse_trade_timestamp(p_entry_time),
    p_created_at
  );
$$;

comment on function public.analytics_realized_sort_ts(text, text, timestamptz) is
  'Chronological P&L realization order: exit_time → entry_time → created_at (distinct from analytics_calendar_day).';

-- ---------------------------------------------------------------------------
-- Canonical mode_effective (extends profile_statistics_resolve_account_mode)
-- ---------------------------------------------------------------------------

create or replace function public.analytics_mode_effective(
  p_account_mode text,
  p_account_type text,
  p_trade_mode text
)
returns text
language sql
immutable
set search_path = public
as $$
  select coalesce(
    public.profile_statistics_resolve_account_mode(
      p_account_mode,
      p_account_type,
      p_trade_mode
    ),
    'unknown'
  );
$$;

comment on function public.analytics_mode_effective(text, text, text) is
  'Canonical analytics mode: accounts.mode → account_type → trade mode; eval→evaluation, replay→sim; unknown stays unknown; never maps unknown→live.';

-- ---------------------------------------------------------------------------
-- trade_daily_stats (private owner aggregates)
-- ---------------------------------------------------------------------------

create table if not exists public.trade_daily_stats (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  account_id uuid null,
  calendar_day date not null,
  mode_effective text not null,
  trade_count integer not null default 0,
  win_count integer not null default 0,
  loss_count integer not null default 0,
  breakeven_count integer not null default 0,
  net_pnl numeric not null default 0,
  gross_profit numeric not null default 0,
  gross_loss numeric not null default 0,
  long_count integer not null default 0,
  long_pnl numeric not null default 0,
  short_count integer not null default 0,
  short_pnl numeric not null default 0,
  sum_rr numeric not null default 0,
  rr_count integer not null default 0,
  sum_hold_seconds bigint not null default 0,
  hold_count integer not null default 0,
  largest_win numeric null,
  largest_loss numeric null,
  updated_at timestamptz not null default now(),
  constraint trade_daily_stats_mode_effective_check check (
    mode_effective in (
      'evaluation',
      'funded',
      'live',
      'sim',
      'backtest',
      'unknown'
    )
  )
);

create unique index if not exists trade_daily_stats_grain_uidx
  on public.trade_daily_stats (user_id, calendar_day, mode_effective, account_id)
  nulls not distinct;

create index if not exists trade_daily_stats_user_day_idx
  on public.trade_daily_stats (user_id, calendar_day);

create index if not exists trade_daily_stats_user_account_idx
  on public.trade_daily_stats (user_id, account_id);

-- ---------------------------------------------------------------------------
-- user_analytics_state
-- ---------------------------------------------------------------------------

create table if not exists public.user_analytics_state (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  revision bigint not null default 0,
  updated_at timestamptz not null default now()
);

-- Contribution row passed between helpers (additive metrics + per-trade extrema).
create type public.trade_analytics_contribution as (
  trade_count integer,
  win_count integer,
  loss_count integer,
  breakeven_count integer,
  net_pnl numeric,
  gross_profit numeric,
  gross_loss numeric,
  long_count integer,
  long_pnl numeric,
  short_count integer,
  short_pnl numeric,
  sum_rr numeric,
  rr_count integer,
  sum_hold_seconds bigint,
  hold_count integer,
  largest_win numeric,
  largest_loss numeric
);

-- ---------------------------------------------------------------------------
-- Bucket resolution + contribution helpers
-- ---------------------------------------------------------------------------

create or replace function public.analytics_trade_account_uuid(p_account_id text)
returns uuid
language sql
immutable
set search_path = public
as $$
  select case
    when nullif(trim(coalesce(p_account_id, '')), '') ~* '^[0-9a-f-]{36}$'
      then nullif(trim(p_account_id), '')::uuid
    else null
  end;
$$;

create or replace function public.analytics_trade_bucket_key(p_trade public.trades)
returns table (
  user_id uuid,
  account_id uuid,
  calendar_day date,
  mode_effective text
)
language plpgsql
stable
set search_path = public
as $$
declare
  v_day date;
  v_mode text;
  v_account_mode text;
begin
  if p_trade.user_id is null then
    return;
  end if;

  v_day := public.analytics_calendar_day(
    p_trade.entry_time,
    p_trade.exit_time,
    p_trade.created_at
  );
  if v_day is null then
    return;
  end if;

  select a.mode
    into v_account_mode
  from public.accounts a
  where a.user_id = p_trade.user_id
    and a.id::text = nullif(trim(coalesce(p_trade.account_id, '')), '')
  limit 1;

  v_mode := public.analytics_mode_effective(
    v_account_mode,
    p_trade.account_type,
    coalesce(p_trade.trade_mode, p_trade.mode)
  );

  user_id := p_trade.user_id;
  account_id := public.analytics_trade_account_uuid(p_trade.account_id);
  calendar_day := v_day;
  mode_effective := v_mode;
  return next;
end;
$$;

create or replace function public.analytics_trade_hold_seconds(p_trade public.trades)
returns bigint
language plpgsql
immutable
set search_path = public
as $$
declare
  v_entry timestamptz;
  v_exit timestamptz;
  v_sec numeric;
begin
  if p_trade.duration_seconds is not null and p_trade.duration_seconds > 0 then
    return p_trade.duration_seconds::bigint;
  end if;
  v_entry := public.analytics_parse_trade_timestamp(p_trade.entry_time);
  v_exit := public.analytics_parse_trade_timestamp(p_trade.exit_time);
  if v_entry is null or v_exit is null then
    return null;
  end if;
  v_sec := extract(epoch from (v_exit - v_entry));
  if v_sec is null or v_sec < 0 then
    return null;
  end if;
  return v_sec::bigint;
end;
$$;

create or replace function public.analytics_trade_contribution(p_trade public.trades)
returns public.trade_analytics_contribution
language plpgsql
stable
set search_path = public
as $$
declare
  v_pnl numeric := coalesce(p_trade.pnl, 0);
  v_dir text := lower(trim(coalesce(p_trade.direction, '')));
  v_hold bigint := public.analytics_trade_hold_seconds(p_trade);
  v_out public.trade_analytics_contribution;
begin
  v_out.trade_count := 1;
  v_out.win_count := case when v_pnl > 0 then 1 else 0 end;
  v_out.loss_count := case when v_pnl < 0 then 1 else 0 end;
  v_out.breakeven_count := case when v_pnl = 0 then 1 else 0 end;
  v_out.net_pnl := v_pnl;
  v_out.gross_profit := case when v_pnl > 0 then v_pnl else 0 end;
  v_out.gross_loss := case when v_pnl < 0 then v_pnl else 0 end;
  v_out.long_count := case when v_dir = 'long' then 1 else 0 end;
  v_out.long_pnl := case when v_dir = 'long' then v_pnl else 0 end;
  v_out.short_count := case when v_dir <> 'long' and v_dir <> '' then 1 else 0 end;
  v_out.short_pnl := case when v_dir <> 'long' and v_dir <> '' then v_pnl else 0 end;
  if p_trade.rr is not null then
    v_out.sum_rr := p_trade.rr;
    v_out.rr_count := 1;
  else
    v_out.sum_rr := 0;
    v_out.rr_count := 0;
  end if;
  if v_hold is not null then
    v_out.sum_hold_seconds := v_hold;
    v_out.hold_count := 1;
  else
    v_out.sum_hold_seconds := 0;
    v_out.hold_count := 0;
  end if;
  v_out.largest_win := case when v_pnl > 0 then v_pnl else null end;
  v_out.largest_loss := case when v_pnl < 0 then v_pnl else null end;
  return v_out;
end;
$$;

create or replace function public.analytics_bump_user_revision(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_analytics_state (user_id, revision, updated_at)
  values (p_user_id, 1, now())
  on conflict (user_id) do update
    set revision = public.user_analytics_state.revision + 1,
        updated_at = now();
end;
$$;

create or replace function public.analytics_refresh_daily_bucket_extrema(
  p_user_id uuid,
  p_account_id uuid,
  p_calendar_day date,
  p_mode_effective text
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.trade_daily_stats s
  set
    largest_win = src.largest_win,
    largest_loss = src.largest_loss,
    updated_at = now()
  from (
    select
      max(t.pnl) filter (where coalesce(t.pnl, 0) > 0) as largest_win,
      min(t.pnl) filter (where coalesce(t.pnl, 0) < 0) as largest_loss
    from public.trades t
    cross join lateral public.analytics_trade_bucket_key(t) b
    where t.user_id = p_user_id
      and b.calendar_day = p_calendar_day
      and b.mode_effective = p_mode_effective
      and b.account_id is not distinct from p_account_id
  ) src
  where s.user_id = p_user_id
    and s.calendar_day = p_calendar_day
    and s.mode_effective = p_mode_effective
    and s.account_id is not distinct from p_account_id;
$$;

create or replace function public.analytics_apply_trade_contribution(
  p_user_id uuid,
  p_account_id uuid,
  p_calendar_day date,
  p_mode_effective text,
  p_sign integer,
  p_contrib public.trade_analytics_contribution
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_trade_count integer;
begin
  if p_sign not in (-1, 1) then
    raise exception 'invalid contribution sign %', p_sign;
  end if;

  insert into public.trade_daily_stats (
    user_id,
    account_id,
    calendar_day,
    mode_effective,
    trade_count,
    win_count,
    loss_count,
    breakeven_count,
    net_pnl,
    gross_profit,
    gross_loss,
    long_count,
    long_pnl,
    short_count,
    short_pnl,
    sum_rr,
    rr_count,
    sum_hold_seconds,
    hold_count,
    largest_win,
    largest_loss,
    updated_at
  )
  values (
    p_user_id,
    p_account_id,
    p_calendar_day,
    p_mode_effective,
    p_sign * coalesce(p_contrib.trade_count, 0),
    p_sign * coalesce(p_contrib.win_count, 0),
    p_sign * coalesce(p_contrib.loss_count, 0),
    p_sign * coalesce(p_contrib.breakeven_count, 0),
    p_sign * coalesce(p_contrib.net_pnl, 0),
    p_sign * coalesce(p_contrib.gross_profit, 0),
    p_sign * coalesce(p_contrib.gross_loss, 0),
    p_sign * coalesce(p_contrib.long_count, 0),
    p_sign * coalesce(p_contrib.long_pnl, 0),
    p_sign * coalesce(p_contrib.short_count, 0),
    p_sign * coalesce(p_contrib.short_pnl, 0),
    p_sign * coalesce(p_contrib.sum_rr, 0),
    p_sign * coalesce(p_contrib.rr_count, 0),
    p_sign * (coalesce(p_contrib.sum_hold_seconds, 0))::bigint,
    p_sign * coalesce(p_contrib.hold_count, 0),
    case when p_sign = 1 then p_contrib.largest_win else null end,
    case when p_sign = 1 then p_contrib.largest_loss else null end,
    now()
  )
  on conflict (user_id, calendar_day, mode_effective, account_id)
  do update set
    trade_count = public.trade_daily_stats.trade_count + excluded.trade_count,
    win_count = public.trade_daily_stats.win_count + excluded.win_count,
    loss_count = public.trade_daily_stats.loss_count + excluded.loss_count,
    breakeven_count = public.trade_daily_stats.breakeven_count + excluded.breakeven_count,
    net_pnl = public.trade_daily_stats.net_pnl + excluded.net_pnl,
    gross_profit = public.trade_daily_stats.gross_profit + excluded.gross_profit,
    gross_loss = public.trade_daily_stats.gross_loss + excluded.gross_loss,
    long_count = public.trade_daily_stats.long_count + excluded.long_count,
    long_pnl = public.trade_daily_stats.long_pnl + excluded.long_pnl,
    short_count = public.trade_daily_stats.short_count + excluded.short_count,
    short_pnl = public.trade_daily_stats.short_pnl + excluded.short_pnl,
    sum_rr = public.trade_daily_stats.sum_rr + excluded.sum_rr,
    rr_count = public.trade_daily_stats.rr_count + excluded.rr_count,
    sum_hold_seconds = public.trade_daily_stats.sum_hold_seconds + excluded.sum_hold_seconds,
    hold_count = public.trade_daily_stats.hold_count + excluded.hold_count,
    largest_win = case
      when excluded.largest_win is null then public.trade_daily_stats.largest_win
      when public.trade_daily_stats.largest_win is null then excluded.largest_win
      else greatest(public.trade_daily_stats.largest_win, excluded.largest_win)
    end,
    largest_loss = case
      when excluded.largest_loss is null then public.trade_daily_stats.largest_loss
      when public.trade_daily_stats.largest_loss is null then excluded.largest_loss
      else least(public.trade_daily_stats.largest_loss, excluded.largest_loss)
    end,
    updated_at = now()
  returning trade_count into v_trade_count;

  if coalesce(v_trade_count, 0) <= 0 then
    delete from public.trade_daily_stats
    where user_id = p_user_id
      and calendar_day = p_calendar_day
      and mode_effective = p_mode_effective
      and account_id is not distinct from p_account_id;
  else
    perform public.analytics_refresh_daily_bucket_extrema(
      p_user_id,
      p_account_id,
      p_calendar_day,
      p_mode_effective
    );
  end if;
end;
$$;

create or replace function public.analytics_sync_trade_daily_stats_from_row(
  p_trade public.trades,
  p_sign integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  b record;
  c public.trade_analytics_contribution;
begin
  if current_setting('app.skip_trade_daily_stats', true) = 'on' then
    return;
  end if;

  select * into b
  from public.analytics_trade_bucket_key(p_trade)
  limit 1;
  if not found then
    return;
  end if;

  c := public.analytics_trade_contribution(p_trade);

  perform public.analytics_apply_trade_contribution(
    b.user_id,
    b.account_id,
    b.calendar_day,
    b.mode_effective,
    p_sign,
    c
  );
end;
$$;

create or replace function public.trades_maintain_trade_daily_stats()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  if tg_op = 'INSERT' then
    perform public.analytics_sync_trade_daily_stats_from_row(new, 1);
    v_user_id := new.user_id;
    if v_user_id is not null then
      perform public.analytics_bump_user_revision(v_user_id);
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    perform public.analytics_sync_trade_daily_stats_from_row(old, -1);
    v_user_id := old.user_id;
    if v_user_id is not null then
      perform public.analytics_bump_user_revision(v_user_id);
    end if;
    return old;
  elsif tg_op = 'UPDATE' then
    perform public.analytics_sync_trade_daily_stats_from_row(old, -1);
    perform public.analytics_sync_trade_daily_stats_from_row(new, 1);
    v_user_id := coalesce(new.user_id, old.user_id);
    if v_user_id is not null then
      perform public.analytics_bump_user_revision(v_user_id);
    end if;
    return new;
  end if;
  return null;
end;
$$;

drop trigger if exists trades_maintain_trade_daily_stats_trg on public.trades;
create trigger trades_maintain_trade_daily_stats_trg
  after insert or update or delete on public.trades
  for each row
  execute function public.trades_maintain_trade_daily_stats();

-- Account mode changes reclassify historical rows — rebuild from raw trades.
create or replace function public.rebuild_trade_daily_stats_for_account(
  p_user_id uuid,
  p_account_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.trade_daily_stats
  where user_id = p_user_id
    and account_id is not distinct from p_account_id;

  insert into public.trade_daily_stats (
    user_id,
    account_id,
    calendar_day,
    mode_effective,
    trade_count,
    win_count,
    loss_count,
    breakeven_count,
    net_pnl,
    gross_profit,
    gross_loss,
    long_count,
    long_pnl,
    short_count,
    short_pnl,
    sum_rr,
    rr_count,
    sum_hold_seconds,
    hold_count,
    largest_win,
    largest_loss,
    updated_at
  )
  select
    b.user_id,
    b.account_id,
    b.calendar_day,
    b.mode_effective,
    count(*)::integer,
    count(*) filter (where coalesce(t.pnl, 0) > 0)::integer,
    count(*) filter (where coalesce(t.pnl, 0) < 0)::integer,
    count(*) filter (where coalesce(t.pnl, 0) = 0)::integer,
    coalesce(sum(t.pnl), 0),
    coalesce(sum(t.pnl) filter (where coalesce(t.pnl, 0) > 0), 0),
    coalesce(sum(t.pnl) filter (where coalesce(t.pnl, 0) < 0), 0),
    count(*) filter (where lower(trim(coalesce(t.direction, ''))) = 'long')::integer,
    coalesce(sum(t.pnl) filter (where lower(trim(coalesce(t.direction, ''))) = 'long'), 0),
    count(*) filter (
      where lower(trim(coalesce(t.direction, ''))) <> 'long'
        and nullif(trim(coalesce(t.direction, '')), '') is not null
    )::integer,
    coalesce(sum(t.pnl) filter (
      where lower(trim(coalesce(t.direction, ''))) <> 'long'
        and nullif(trim(coalesce(t.direction, '')), '') is not null
    ), 0),
    coalesce(sum(t.rr) filter (where t.rr is not null), 0),
    count(*) filter (where t.rr is not null)::integer,
    coalesce(sum(public.analytics_trade_hold_seconds(t)) filter (
      where public.analytics_trade_hold_seconds(t) is not null
    ), 0)::bigint,
    count(*) filter (where public.analytics_trade_hold_seconds(t) is not null)::integer,
    max(t.pnl) filter (where coalesce(t.pnl, 0) > 0),
    min(t.pnl) filter (where coalesce(t.pnl, 0) < 0),
    now()
  from public.trades t
  cross join lateral public.analytics_trade_bucket_key(t) b
  where t.user_id = p_user_id
    and b.account_id is not distinct from p_account_id
  group by b.user_id, b.account_id, b.calendar_day, b.mode_effective;

  perform public.analytics_bump_user_revision(p_user_id);
end;
$$;

create or replace function public.accounts_rebuild_trade_daily_stats_on_mode_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE'
     and new.mode is distinct from old.mode then
    perform public.rebuild_trade_daily_stats_for_account(new.user_id, new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists accounts_rebuild_trade_daily_stats_on_mode_change_trg on public.accounts;
create trigger accounts_rebuild_trade_daily_stats_on_mode_change_trg
  after update of mode on public.accounts
  for each row
  execute function public.accounts_rebuild_trade_daily_stats_on_mode_change();

create or replace function public.rebuild_trade_daily_stats_for_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.trade_daily_stats where user_id = p_user_id;

  insert into public.trade_daily_stats (
    user_id,
    account_id,
    calendar_day,
    mode_effective,
    trade_count,
    win_count,
    loss_count,
    breakeven_count,
    net_pnl,
    gross_profit,
    gross_loss,
    long_count,
    long_pnl,
    short_count,
    short_pnl,
    sum_rr,
    rr_count,
    sum_hold_seconds,
    hold_count,
    largest_win,
    largest_loss,
    updated_at
  )
  select
    b.user_id,
    b.account_id,
    b.calendar_day,
    b.mode_effective,
    count(*)::integer,
    count(*) filter (where coalesce(t.pnl, 0) > 0)::integer,
    count(*) filter (where coalesce(t.pnl, 0) < 0)::integer,
    count(*) filter (where coalesce(t.pnl, 0) = 0)::integer,
    coalesce(sum(t.pnl), 0),
    coalesce(sum(t.pnl) filter (where coalesce(t.pnl, 0) > 0), 0),
    coalesce(sum(t.pnl) filter (where coalesce(t.pnl, 0) < 0), 0),
    count(*) filter (where lower(trim(coalesce(t.direction, ''))) = 'long')::integer,
    coalesce(sum(t.pnl) filter (where lower(trim(coalesce(t.direction, ''))) = 'long'), 0),
    count(*) filter (
      where lower(trim(coalesce(t.direction, ''))) <> 'long'
        and nullif(trim(coalesce(t.direction, '')), '') is not null
    )::integer,
    coalesce(sum(t.pnl) filter (
      where lower(trim(coalesce(t.direction, ''))) <> 'long'
        and nullif(trim(coalesce(t.direction, '')), '') is not null
    ), 0),
    coalesce(sum(t.rr) filter (where t.rr is not null), 0),
    count(*) filter (where t.rr is not null)::integer,
    coalesce(sum(public.analytics_trade_hold_seconds(t)) filter (
      where public.analytics_trade_hold_seconds(t) is not null
    ), 0)::bigint,
    count(*) filter (where public.analytics_trade_hold_seconds(t) is not null)::integer,
    max(t.pnl) filter (where coalesce(t.pnl, 0) > 0),
    min(t.pnl) filter (where coalesce(t.pnl, 0) < 0),
    now()
  from public.trades t
  cross join lateral public.analytics_trade_bucket_key(t) b
  where t.user_id = p_user_id
  group by b.user_id, b.account_id, b.calendar_day, b.mode_effective;

  perform public.analytics_bump_user_revision(p_user_id);
end;
$$;

-- Staged backfill helper (run from ops/job; not executed inline here for prod safety).
create or replace function public.backfill_trade_daily_stats_batch(p_limit integer default 50)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_count integer := 0;
begin
  for v_uid in
    select p.id
    from public.profiles p
    where not exists (
      select 1 from public.user_analytics_state u where u.user_id = p.id
    )
    order by p.created_at nulls last, p.id
    limit greatest(1, least(coalesce(p_limit, 50), 500))
  loop
    perform public.rebuild_trade_daily_stats_for_user(v_uid);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

comment on function public.backfill_trade_daily_stats_batch(integer) is
  'Phase 1B staged backfill: rebuild trade_daily_stats for users without user_analytics_state. Call repeatedly from a job until it returns 0.';

-- ---------------------------------------------------------------------------
-- RLS — private owner analytics
-- ---------------------------------------------------------------------------

alter table public.trade_daily_stats enable row level security;
alter table public.user_analytics_state enable row level security;

drop policy if exists trade_daily_stats_select_own on public.trade_daily_stats;
create policy trade_daily_stats_select_own
  on public.trade_daily_stats
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists user_analytics_state_select_own on public.user_analytics_state;
create policy user_analytics_state_select_own
  on public.user_analytics_state
  for select
  to authenticated
  using (user_id = (select auth.uid()));

-- Maintenance writes via SECURITY DEFINER triggers/functions only (no client insert/update policies).

-- ---------------------------------------------------------------------------
-- Shadow read RPC
-- ---------------------------------------------------------------------------

create or replace function public.rpc_v1_analytics_daily_range_bootstrap(
  p_start date,
  p_end date,
  p_account_id uuid default null,
  p_mode text default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_mode text := nullif(lower(trim(coalesce(p_mode, ''))), '');
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_start is null or p_end is null or p_end < p_start then
    raise exception 'invalid_date_range' using errcode = '22023';
  end if;

  return (
    with state as (
      select coalesce(u.revision, 0) as revision, u.updated_at
      from public.user_analytics_state u
      where u.user_id = v_uid
    ),
    rows as (
      select
        s.calendar_day,
        s.account_id,
        s.mode_effective,
        s.trade_count,
        s.win_count,
        s.loss_count,
        s.breakeven_count,
        s.net_pnl,
        s.gross_profit,
        s.gross_loss,
        s.long_count,
        s.long_pnl,
        s.short_count,
        s.short_pnl,
        s.sum_rr,
        s.rr_count,
        s.sum_hold_seconds,
        s.hold_count,
        s.largest_win,
        s.largest_loss,
        s.updated_at
      from public.trade_daily_stats s
      where s.user_id = v_uid
        and s.calendar_day between p_start and p_end
        and (p_account_id is null or s.account_id is not distinct from p_account_id)
        and (v_mode is null or s.mode_effective = v_mode)
      order by s.calendar_day, s.mode_effective, s.account_id nulls first
    ),
    summary as (
      select
        coalesce(sum(r.trade_count), 0)::integer as trade_count,
        coalesce(sum(r.win_count), 0)::integer as win_count,
        coalesce(sum(r.loss_count), 0)::integer as loss_count,
        coalesce(sum(r.breakeven_count), 0)::integer as breakeven_count,
        coalesce(sum(r.net_pnl), 0) as net_pnl,
        coalesce(sum(r.gross_profit), 0) as gross_profit,
        coalesce(sum(r.gross_loss), 0) as gross_loss,
        coalesce(sum(r.long_count), 0)::integer as long_count,
        coalesce(sum(r.long_pnl), 0) as long_pnl,
        coalesce(sum(r.short_count), 0)::integer as short_count,
        coalesce(sum(r.short_pnl), 0) as short_pnl,
        coalesce(sum(r.sum_rr), 0) as sum_rr,
        coalesce(sum(r.rr_count), 0)::integer as rr_count,
        coalesce(sum(r.sum_hold_seconds), 0)::bigint as sum_hold_seconds,
        coalesce(sum(r.hold_count), 0)::integer as hold_count,
        max(r.largest_win) as largest_win,
        min(r.largest_loss) as largest_loss
      from rows r
    )
    select jsonb_build_object(
      'revision', (select revision from state),
      'state_updated_at', (select updated_at from state),
      'start', p_start,
      'end', p_end,
      'account_id', p_account_id,
      'mode', v_mode,
      'days', coalesce((select jsonb_agg(to_jsonb(r)) from rows r), '[]'::jsonb),
      'summary', (select to_jsonb(summary) from summary)
    )
  );
end;
$$;

revoke all on function public.rpc_v1_analytics_daily_range_bootstrap(date, date, uuid, text) from public;
grant execute on function public.rpc_v1_analytics_daily_range_bootstrap(date, date, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Shadow comparison (owner-only validation)
-- ---------------------------------------------------------------------------

create or replace function public.rpc_v1_analytics_shadow_compare_range(
  p_start date,
  p_end date,
  p_account_id uuid default null,
  p_mode text default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_mode text := nullif(lower(trim(coalesce(p_mode, ''))), '');
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  return (
    with raw_normal as (
      select t.*
      from public.trades t
      cross join lateral public.analytics_trade_bucket_key(t) b
      where t.user_id = v_uid
        and b.calendar_day between p_start and p_end
        and (p_account_id is null or b.account_id is not distinct from p_account_id)
        and (v_mode is null or b.mode_effective = v_mode)
        and (v_mode is not null or b.mode_effective <> 'backtest')
    ),
    raw_legacy_day as (
      select t.*
      from public.trades t
      where t.user_id = v_uid
        and public.analytics_legacy_trading_day_key(
          t.entry_time, t.exit_time, t.created_at
        ) between p_start and p_end
        and (p_account_id is null or public.analytics_trade_account_uuid(t.account_id) is not distinct from p_account_id)
        and (
          v_mode is null
          or public.analytics_mode_effective(
            (select a.mode from public.accounts a where a.id::text = nullif(trim(t.account_id), '') and a.user_id = t.user_id limit 1),
            t.account_type,
            coalesce(t.trade_mode, t.mode)
          ) = v_mode
        )
        and (v_mode is not null or public.analytics_mode_effective(
          (select a.mode from public.accounts a where a.id::text = nullif(trim(t.account_id), '') and a.user_id = t.user_id limit 1),
          t.account_type,
          coalesce(t.trade_mode, t.mode)
        ) <> 'backtest')
    ),
    agg as (
      select * from public.trade_daily_stats s
      where s.user_id = v_uid
        and s.calendar_day between p_start and p_end
        and (p_account_id is null or s.account_id is not distinct from p_account_id)
        and (v_mode is null or s.mode_effective = v_mode)
        and (v_mode is not null or s.mode_effective <> 'backtest')
    ),
    m_raw_normal as (
      select
        count(*)::integer as trade_count,
        count(*) filter (where coalesce(pnl, 0) > 0)::integer as win_count,
        count(*) filter (where coalesce(pnl, 0) < 0)::integer as loss_count,
        count(*) filter (where coalesce(pnl, 0) = 0)::integer as breakeven_count,
        coalesce(sum(pnl), 0) as net_pnl,
        coalesce(sum(pnl) filter (where coalesce(pnl, 0) > 0), 0) as gross_profit,
        coalesce(sum(pnl) filter (where coalesce(pnl, 0) < 0), 0) as gross_loss
      from raw_normal
    ),
    m_raw_legacy as (
      select
        count(*)::integer as trade_count,
        count(*) filter (where coalesce(pnl, 0) > 0)::integer as win_count,
        count(*) filter (where coalesce(pnl, 0) < 0)::integer as loss_count,
        count(*) filter (where coalesce(pnl, 0) = 0)::integer as breakeven_count,
        coalesce(sum(pnl), 0) as net_pnl,
        coalesce(sum(pnl) filter (where coalesce(pnl, 0) > 0), 0) as gross_profit,
        coalesce(sum(pnl) filter (where coalesce(pnl, 0) < 0), 0) as gross_loss
      from raw_legacy_day
    ),
    m_agg as (
      select
        coalesce(sum(trade_count), 0)::integer as trade_count,
        coalesce(sum(win_count), 0)::integer as win_count,
        coalesce(sum(loss_count), 0)::integer as loss_count,
        coalesce(sum(breakeven_count), 0)::integer as breakeven_count,
        coalesce(sum(net_pnl), 0) as net_pnl,
        coalesce(sum(gross_profit), 0) as gross_profit,
        coalesce(sum(gross_loss), 0) as gross_loss,
        coalesce(sum(long_count), 0)::integer as long_count,
        coalesce(sum(long_pnl), 0) as long_pnl,
        coalesce(sum(short_count), 0)::integer as short_count,
        coalesce(sum(short_pnl), 0) as short_pnl,
        coalesce(sum(sum_rr), 0) as sum_rr,
        coalesce(sum(rr_count), 0)::integer as rr_count,
        coalesce(sum(sum_hold_seconds), 0)::bigint as sum_hold_seconds,
        coalesce(sum(hold_count), 0)::integer as hold_count,
        max(largest_win) as largest_win,
        min(largest_loss) as largest_loss
      from agg
    )
    select jsonb_build_object(
      'start', p_start,
      'end', p_end,
      'account_id', p_account_id,
      'mode', v_mode,
      'date_semantics_note',
        'normal_calendar_day uses analytics_calendar_day (no 18:00 ET roll). legacy_trading_day uses analytics_legacy_trading_day_key (Calendar/prop-firm). Mismatch between legacy_trading_day and aggregate is expected until Phase 3.',
      'aggregate', (select to_jsonb(m_agg) from m_agg),
      'raw_normal_calendar', (select to_jsonb(m_raw_normal) from m_raw_normal),
      'raw_legacy_trading_day', (select to_jsonb(m_raw_legacy) from m_raw_legacy),
      'parity_aggregate_vs_raw_normal', (
        select jsonb_build_object(
          'trade_count', (a.trade_count = r.trade_count),
          'win_count', (a.win_count = r.win_count),
          'loss_count', (a.loss_count = r.loss_count),
          'breakeven_count', (a.breakeven_count = r.breakeven_count),
          'net_pnl', (a.net_pnl = r.net_pnl),
          'gross_profit', (a.gross_profit = r.gross_profit),
          'gross_loss', (a.gross_loss = r.gross_loss)
        )
        from m_agg a, m_raw_normal r
      ),
      'expected_legacy_day_mismatch', (
        select (r.trade_count is distinct from l.trade_count)
          or (r.net_pnl is distinct from l.net_pnl)
        from m_raw_normal r, m_raw_legacy l
      )
    )
  );
end;
$$;

revoke all on function public.rpc_v1_analytics_shadow_compare_range(date, date, uuid, text) from public;
grant execute on function public.rpc_v1_analytics_shadow_compare_range(date, date, uuid, text) to authenticated;

revoke all on function public.rebuild_trade_daily_stats_for_user(uuid) from public, anon, authenticated;
grant execute on function public.rebuild_trade_daily_stats_for_user(uuid) to service_role;

revoke all on function public.rebuild_trade_daily_stats_for_account(uuid, uuid) from public, anon, authenticated;
grant execute on function public.rebuild_trade_daily_stats_for_account(uuid, uuid) to service_role;

revoke all on function public.backfill_trade_daily_stats_batch(integer) from public, anon, authenticated;
grant execute on function public.backfill_trade_daily_stats_batch(integer) to service_role;
