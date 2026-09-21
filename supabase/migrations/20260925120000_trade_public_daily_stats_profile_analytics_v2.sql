-- Phase 7B — Public Profile analytical foundation (server-only; no client cutover).
-- Maintains public-only daily aggregates + profile public revision + V2 RPCs (shadow).

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.trade_public_daily_stats (
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
  constraint trade_public_daily_stats_mode_effective_check check (
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

create unique index if not exists trade_public_daily_stats_grain_uidx
  on public.trade_public_daily_stats (user_id, calendar_day, mode_effective, account_id)
  nulls not distinct;

create index if not exists trade_public_daily_stats_user_day_idx
  on public.trade_public_daily_stats (user_id, calendar_day);

create index if not exists trade_public_daily_stats_user_account_idx
  on public.trade_public_daily_stats (user_id, account_id);

comment on table public.trade_public_daily_stats is
  'Owner-scoped daily aggregates for is_public=true trades only (Profile public analytics). Not client-readable.';

create table if not exists public.profile_public_analytics_state (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  revision bigint not null default 1,
  updated_at timestamptz not null default now()
);

comment on table public.profile_public_analytics_state is
  'Revision for public Profile analytical universe only. Not user_analytics_state; not client-readable.';

-- ---------------------------------------------------------------------------
-- Eligibility + public revision bump
-- ---------------------------------------------------------------------------

create or replace function public.analytics_trade_eligible_public_profile(p_trade public.trades)
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(p_trade.is_public, false) = true;
$$;

create or replace function public.analytics_bump_profile_public_revision(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user_id is null then
    return;
  end if;
  insert into public.profile_public_analytics_state (user_id, revision, updated_at)
  values (p_user_id, 1, now())
  on conflict (user_id) do update
    set revision = public.profile_public_analytics_state.revision + 1,
        updated_at = now();
end;
$$;

create or replace function public.analytics_trade_row_affects_public_stats(
  p_old public.trades,
  p_new public.trades
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select
    coalesce(p_old.is_public, false) is distinct from coalesce(p_new.is_public, false)
    or (
      (coalesce(p_old.is_public, false) or coalesce(p_new.is_public, false))
      and public.analytics_trade_row_affects_stats(p_old, p_new)
    );
$$;

-- ---------------------------------------------------------------------------
-- Public daily stats maintenance (mirrors trade_daily_stats pipeline)
-- ---------------------------------------------------------------------------

create or replace function public.analytics_refresh_public_daily_bucket_extrema(
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
  update public.trade_public_daily_stats s
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
      and coalesce(t.is_public, false) = true
      and b.calendar_day = p_calendar_day
      and b.mode_effective = p_mode_effective
      and b.account_id is not distinct from p_account_id
  ) src
  where s.user_id = p_user_id
    and s.calendar_day = p_calendar_day
    and s.mode_effective = p_mode_effective
    and s.account_id is not distinct from p_account_id;
$$;

create or replace function public.analytics_apply_trade_public_contribution(
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

  insert into public.trade_public_daily_stats (
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
    trade_count = public.trade_public_daily_stats.trade_count + excluded.trade_count,
    win_count = public.trade_public_daily_stats.win_count + excluded.win_count,
    loss_count = public.trade_public_daily_stats.loss_count + excluded.loss_count,
    breakeven_count = public.trade_public_daily_stats.breakeven_count + excluded.breakeven_count,
    net_pnl = public.trade_public_daily_stats.net_pnl + excluded.net_pnl,
    gross_profit = public.trade_public_daily_stats.gross_profit + excluded.gross_profit,
    gross_loss = public.trade_public_daily_stats.gross_loss + excluded.gross_loss,
    long_count = public.trade_public_daily_stats.long_count + excluded.long_count,
    long_pnl = public.trade_public_daily_stats.long_pnl + excluded.long_pnl,
    short_count = public.trade_public_daily_stats.short_count + excluded.short_count,
    short_pnl = public.trade_public_daily_stats.short_pnl + excluded.short_pnl,
    sum_rr = public.trade_public_daily_stats.sum_rr + excluded.sum_rr,
    rr_count = public.trade_public_daily_stats.rr_count + excluded.rr_count,
    sum_hold_seconds = public.trade_public_daily_stats.sum_hold_seconds + excluded.sum_hold_seconds,
    hold_count = public.trade_public_daily_stats.hold_count + excluded.hold_count,
    largest_win = case
      when excluded.largest_win is null then public.trade_public_daily_stats.largest_win
      when public.trade_public_daily_stats.largest_win is null then excluded.largest_win
      else greatest(public.trade_public_daily_stats.largest_win, excluded.largest_win)
    end,
    largest_loss = case
      when excluded.largest_loss is null then public.trade_public_daily_stats.largest_loss
      when public.trade_public_daily_stats.largest_loss is null then excluded.largest_loss
      else least(public.trade_public_daily_stats.largest_loss, excluded.largest_loss)
    end,
    updated_at = now()
  returning trade_count into v_trade_count;

  if coalesce(v_trade_count, 0) <= 0 then
    delete from public.trade_public_daily_stats
    where user_id = p_user_id
      and calendar_day = p_calendar_day
      and mode_effective = p_mode_effective
      and account_id is not distinct from p_account_id;
  else
    perform public.analytics_refresh_public_daily_bucket_extrema(
      p_user_id,
      p_account_id,
      p_calendar_day,
      p_mode_effective
    );
  end if;
end;
$$;

create or replace function public.analytics_sync_trade_public_daily_stats_from_row(
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

  if not public.analytics_trade_eligible_public_profile(p_trade) then
    return;
  end if;

  select * into b
  from public.analytics_trade_bucket_key(p_trade)
  limit 1;
  if not found then
    return;
  end if;

  c := public.analytics_trade_contribution(p_trade);

  perform public.analytics_apply_trade_public_contribution(
    b.user_id,
    b.account_id,
    b.calendar_day,
    b.mode_effective,
    p_sign,
    c
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Rebuild helpers
-- ---------------------------------------------------------------------------

create or replace function public.rebuild_trade_public_daily_stats_for_account(
  p_user_id uuid,
  p_account_id uuid,
  p_bump_revision boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.trade_public_daily_stats
  where user_id = p_user_id
    and account_id is not distinct from p_account_id;

  insert into public.trade_public_daily_stats (
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
    and coalesce(t.is_public, false) = true
    and b.account_id is not distinct from p_account_id
  group by b.user_id, b.account_id, b.calendar_day, b.mode_effective;

  if p_bump_revision
     and exists (
       select 1
       from public.trades t
       where t.user_id = p_user_id
         and coalesce(t.is_public, false) = true
     ) then
    perform public.analytics_bump_profile_public_revision(p_user_id);
  end if;
end;
$$;

create or replace function public.rebuild_trade_public_daily_stats_for_user(
  p_user_id uuid,
  p_bump_revision boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.trade_public_daily_stats where user_id = p_user_id;

  insert into public.trade_public_daily_stats (
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
    and coalesce(t.is_public, false) = true
  group by b.user_id, b.account_id, b.calendar_day, b.mode_effective;

  if not exists (
    select 1 from public.profile_public_analytics_state s where s.user_id = p_user_id
  ) then
    insert into public.profile_public_analytics_state (user_id, revision, updated_at)
    values (p_user_id, 1, now())
    on conflict (user_id) do nothing;
  end if;

  if p_bump_revision
     and exists (
       select 1
       from public.trades t
       where t.user_id = p_user_id
         and coalesce(t.is_public, false) = true
     ) then
    perform public.analytics_bump_profile_public_revision(p_user_id);
  end if;
end;
$$;

create or replace function public.backfill_trade_public_daily_stats_batch(p_limit integer default 50)
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
      select 1 from public.profile_public_analytics_state u where u.user_id = p.id
    )
    order by p.created_at nulls last, p.id
    limit greatest(1, least(coalesce(p_limit, 50), 500))
  loop
    perform public.rebuild_trade_public_daily_stats_for_user(v_uid, false);
    insert into public.profile_public_analytics_state (user_id, revision, updated_at)
    values (v_uid, 1, now())
    on conflict (user_id) do nothing;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

comment on function public.backfill_trade_public_daily_stats_batch(integer) is
  'Phase 7B staged backfill: rebuild trade_public_daily_stats for users without profile_public_analytics_state.';

create or replace function public.rebuild_trade_public_daily_stats_all_users()
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
    perform public.rebuild_trade_public_daily_stats_for_user(v_uid, false);
    insert into public.profile_public_analytics_state (user_id, revision, updated_at)
    values (v_uid, 1, now())
    on conflict (user_id) do nothing;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- ---------------------------------------------------------------------------
-- Trades trigger — extend owner daily stats maintenance with public slice
-- ---------------------------------------------------------------------------

create or replace function public.trades_maintain_trade_daily_stats()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_bump boolean := false;
  v_bump_public boolean := false;
begin
  if tg_op = 'INSERT' then
    perform public.analytics_sync_trade_daily_stats_from_row(new, 1);
    perform public.analytics_sync_trade_public_daily_stats_from_row(new, 1);
    v_user_id := new.user_id;
    v_bump := new.user_id is not null;
    v_bump_public := coalesce(new.is_public, false) and new.user_id is not null;
  elsif tg_op = 'DELETE' then
    perform public.analytics_sync_trade_daily_stats_from_row(old, -1);
    perform public.analytics_sync_trade_public_daily_stats_from_row(old, -1);
    v_user_id := old.user_id;
    v_bump := old.user_id is not null;
    v_bump_public := coalesce(old.is_public, false) and old.user_id is not null;
  elsif tg_op = 'UPDATE' then
    if public.analytics_trade_row_affects_stats(old, new) then
      perform public.analytics_sync_trade_daily_stats_from_row(old, -1);
      perform public.analytics_sync_trade_daily_stats_from_row(new, 1);
      v_user_id := coalesce(new.user_id, old.user_id);
      v_bump := v_user_id is not null;
    end if;
    if public.analytics_trade_row_affects_public_stats(old, new) then
      if coalesce(old.is_public, false) then
        perform public.analytics_sync_trade_public_daily_stats_from_row(old, -1);
      end if;
      if coalesce(new.is_public, false) then
        perform public.analytics_sync_trade_public_daily_stats_from_row(new, 1);
      end if;
      v_user_id := coalesce(new.user_id, old.user_id);
      v_bump_public := v_user_id is not null;
    end if;
  end if;

  if v_bump then
    perform public.analytics_bump_user_revision(v_user_id);
  end if;
  if v_bump_public then
    perform public.analytics_bump_profile_public_revision(v_user_id);
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
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
    perform public.rebuild_trade_public_daily_stats_for_account(new.user_id, new.id);
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Profile visibility (same gate as rpc_v1_profile_statistics_bootstrap)
-- ---------------------------------------------------------------------------

create or replace function public.profile_viewer_can_view_trades(p_profile_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(
    (
      select (
        auth.uid() = p_profile_id
        or coalesce(p.is_private, false) = false
        or exists (
          select 1
          from public.followers f
          where f.follower_id = auth.uid()
            and f.following_id = p_profile_id
        )
      )
      from public.profiles p
      where p.id = p_profile_id
    ),
    false
  );
$$;

-- ---------------------------------------------------------------------------
-- Public daily rollup for Profile mode filters
-- ---------------------------------------------------------------------------

create or replace function public.profile_public_daily_stats_mode_rollup(
  p_profile_id uuid,
  p_filter_mode text
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'filtered_trade_count', coalesce(sum(s.trade_count), 0),
    'wins', coalesce(sum(s.win_count), 0),
    'loss_count', coalesce(sum(s.loss_count), 0),
    'long_trades', coalesce(sum(s.long_count), 0),
    'total_pnl', coalesce(sum(s.net_pnl), 0),
    'gross_wins', coalesce(sum(s.gross_profit), 0),
    'gross_losses', coalesce(sum(s.gross_loss), 0),
    'biggest_win', coalesce(max(s.largest_win), 0),
    'biggest_loss', min(s.largest_loss) filter (where s.largest_loss is not null),
    'daily_rows_scanned', count(*)::integer
  )
  from public.trade_public_daily_stats s
  where s.user_id = p_profile_id
    and public.profile_statistics_trade_matches_mode(p_filter_mode, s.mode_effective);
$$;

-- ---------------------------------------------------------------------------
-- rpc_v1_profile_public_analytics_revision
-- ---------------------------------------------------------------------------

create or replace function public.rpc_v1_profile_public_analytics_revision(
  p_profile_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_viewer uuid := auth.uid();
  v_can_view boolean := false;
  v_revision bigint := null;
  v_updated_at timestamptz := null;
  v_server_time text := to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
begin
  if p_profile_id is null then
    raise exception 'invalid_profile_id' using errcode = '22023';
  end if;

  v_can_view := public.profile_viewer_can_view_trades(p_profile_id);

  if v_can_view then
    select s.revision, s.updated_at
      into v_revision, v_updated_at
    from public.profile_public_analytics_state s
    where s.user_id = p_profile_id;
  end if;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'found', v_can_view,
      'server_time', v_server_time,
      'viewer_id', v_viewer
    ),
    'data', jsonb_build_object(
      'profile_id', p_profile_id,
      'revision', case when v_can_view then coalesce(v_revision, 1) else null end,
      'updated_at', case when v_can_view then v_updated_at else null end
    )
  );
end;
$$;

comment on function public.rpc_v1_profile_public_analytics_revision(uuid) is
  'Tiny public Profile analytics revision after visibility gate. Does not expose user_analytics_state.';

-- ---------------------------------------------------------------------------
-- rpc_v1_profile_analytics_bootstrap_v2
-- ---------------------------------------------------------------------------

create or replace function public.rpc_v1_profile_analytics_bootstrap_v2(
  p_profile_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_viewer uuid := auth.uid();
  v_can_view boolean := false;
  v_modes jsonb := '{}'::jsonb;
  v_mode text;
  v_mode_list text[] := array['all', 'eval', 'funded', 'live', 'sim', 'backtest'];
  v_rollup jsonb;
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
  v_public_revision bigint := null;
  v_public_updated_at timestamptz := null;
  v_server_time text := to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
begin
  if p_profile_id is null then
    raise exception 'invalid_profile_id' using errcode = '22023';
  end if;

  v_can_view := public.profile_viewer_can_view_trades(p_profile_id);

  if not v_can_view then
    return jsonb_build_object(
      'meta', jsonb_build_object(
        'contract_version', 'v2',
        'found', false,
        'server_time', v_server_time,
        'viewer_id', v_viewer,
        'public_revision', null,
        'public_updated_at', null
      ),
      'data', jsonb_build_object('profile_id', p_profile_id, 'modes', '{}'::jsonb)
    );
  end if;

  select s.revision, s.updated_at
    into v_public_revision, v_public_updated_at
  from public.profile_public_analytics_state s
  where s.user_id = p_profile_id;

  foreach v_mode in array v_mode_list loop
    v_rollup := public.profile_public_daily_stats_mode_rollup(p_profile_id, v_mode);

    v_total := coalesce((v_rollup->>'filtered_trade_count')::integer, 0);
    v_wins := coalesce((v_rollup->>'wins')::integer, 0);
    v_loss_count := coalesce((v_rollup->>'loss_count')::integer, 0);
    v_long_trades := coalesce((v_rollup->>'long_trades')::integer, 0);
    v_total_pnl := coalesce((v_rollup->>'total_pnl')::numeric, 0);
    v_gross_wins := coalesce((v_rollup->>'gross_wins')::numeric, 0);
    v_gross_losses := coalesce((v_rollup->>'gross_losses')::numeric, 0);
    v_biggest_win := coalesce((v_rollup->>'biggest_win')::numeric, 0);
    v_biggest_loss := (v_rollup->>'biggest_loss')::numeric;

    if v_total > 0 then
      v_win_rate := round(v_wins::numeric / v_total::numeric, 8);
      v_profit_per_trade := round(v_total_pnl / v_total::numeric, 8);
    else
      v_win_rate := null;
      v_profit_per_trade := null;
    end if;

    if v_gross_losses < 0 then
      v_profit_factor := round(v_gross_wins / abs(v_gross_losses), 8);
    else
      v_profit_factor := null;
    end if;

    if v_wins > 0 then
      v_average_winner := round(v_gross_wins / v_wins::numeric, 8);
    else
      v_average_winner := null;
    end if;

    if v_loss_count > 0 then
      v_average_loser := round(v_gross_losses / v_loss_count::numeric, 8);
    else
      v_average_loser := null;
    end if;

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

    for rec in
      select b.pnl, b.created_at, b.trade_id, b.session_raw
      from public.profile_statistics_public_trades(p_profile_id) b
      where public.profile_statistics_trade_matches_mode(v_mode, b.acct_mode)
      order by b.created_at asc, b.trade_id asc
    loop
      v_running := v_running + coalesce(rec.pnl, 0);
      v_equity := v_equity || jsonb_build_array(
        jsonb_build_object(
          'index', v_idx,
          'equity', v_running,
          'date', to_char(rec.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
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
        'equity_data', v_equity,
        'aggregate_source', 'trade_public_daily_stats',
        'daily_rows_scanned', coalesce((v_rollup->>'daily_rows_scanned')::integer, 0)
      )
    );
  end loop;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v2',
      'found', true,
      'server_time', v_server_time,
      'viewer_id', v_viewer,
      'public_revision', coalesce(v_public_revision, 1),
      'public_updated_at', v_public_updated_at
    ),
    'data', jsonb_build_object(
      'profile_id', p_profile_id,
      'modes', v_modes
    )
  );
end;
$$;

comment on function public.rpc_v1_profile_analytics_bootstrap_v2(uuid) is
  'Profile Statistics V2 — additive metrics from trade_public_daily_stats; order/session metrics from authoritative public trade pass. Shadow-only until client cutover.';

-- ---------------------------------------------------------------------------
-- Shadow validation (service_role)
-- ---------------------------------------------------------------------------

create or replace function public.profile_public_daily_stats_raw_parity(
  p_profile_id uuid,
  p_filter_mode text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agg jsonb;
  v_raw jsonb;
begin
  v_agg := public.profile_public_daily_stats_mode_rollup(p_profile_id, p_filter_mode);

  select jsonb_build_object(
    'filtered_trade_count', count(*)::integer,
    'wins', count(*) filter (where coalesce(b.pnl, 0) > 0)::integer,
    'loss_count', count(*) filter (where coalesce(b.pnl, 0) < 0)::integer,
    'long_trades', count(*) filter (where b.is_long)::integer,
    'total_pnl', coalesce(sum(coalesce(b.pnl, 0)), 0),
    'gross_wins', coalesce(sum(b.pnl) filter (where coalesce(b.pnl, 0) > 0), 0),
    'gross_losses', coalesce(sum(b.pnl) filter (where coalesce(b.pnl, 0) < 0), 0),
    'biggest_win', coalesce(max(b.pnl), 0),
    'biggest_loss', min(b.pnl) filter (where coalesce(b.pnl, 0) < 0)
  )
  into v_raw
  from public.profile_statistics_public_trades(p_profile_id) b
  where public.profile_statistics_trade_matches_mode(p_filter_mode, b.acct_mode);

  return jsonb_build_object(
    'profile_id', p_profile_id,
    'mode', p_filter_mode,
    'aggregate', v_agg,
    'raw_public_trades', v_raw,
    'parity', jsonb_build_object(
      'filtered_trade_count', (v_agg->>'filtered_trade_count')::integer = (v_raw->>'filtered_trade_count')::integer,
      'wins', (v_agg->>'wins')::integer = (v_raw->>'wins')::integer,
      'loss_count', (v_agg->>'loss_count')::integer = (v_raw->>'loss_count')::integer,
      'long_trades', (v_agg->>'long_trades')::integer = (v_raw->>'long_trades')::integer,
      'total_pnl', public.analytics_numeric_near((v_agg->>'total_pnl')::numeric, (v_raw->>'total_pnl')::numeric),
      'gross_wins', public.analytics_numeric_near((v_agg->>'gross_wins')::numeric, (v_raw->>'gross_wins')::numeric),
      'gross_losses', public.analytics_numeric_near((v_agg->>'gross_losses')::numeric, (v_raw->>'gross_losses')::numeric),
      'biggest_win', public.analytics_numeric_near((v_agg->>'biggest_win')::numeric, (v_raw->>'biggest_win')::numeric, 0.0001),
      'biggest_loss', public.analytics_numeric_near((v_agg->>'biggest_loss')::numeric, (v_raw->>'biggest_loss')::numeric, 0.0001)
        or ((v_agg->>'biggest_loss') is null and (v_raw->>'biggest_loss') is null)
    )
  );
end;
$$;

create or replace function public.profile_analytics_v2_shadow_compare(
  p_profile_id uuid,
  p_viewer_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_mode text;
  v_mode_list text[] := array['all', 'eval', 'funded', 'live', 'sim', 'backtest'];
  v_v1 jsonb;
  v_v2 jsonb;
  v_modes jsonb := '{}'::jsonb;
  v_mode_v1 jsonb;
  v_mode_v2 jsonb;
  v_parity jsonb;
  v_all_additive boolean := true;
  v_raw_parity jsonb;
begin
  if p_viewer_id is not null then
    perform set_config('request.jwt.claim.sub', p_viewer_id::text, true);
  end if;

  v_v1 := public.rpc_v1_profile_statistics_bootstrap(p_profile_id);
  v_v2 := public.rpc_v1_profile_analytics_bootstrap_v2(p_profile_id);

  foreach v_mode in array v_mode_list loop
    v_mode_v1 := v_v1->'data'->'modes'->v_mode;
    v_mode_v2 := v_v2->'data'->'modes'->v_mode;

    if v_mode_v1 is null or v_mode_v2 is null then
      v_parity := jsonb_build_object('missing_mode', true);
      v_all_additive := false;
    else
      v_parity := jsonb_build_object(
        'filtered_trade_count', (v_mode_v1->>'filtered_trade_count')::integer = (v_mode_v2->>'filtered_trade_count')::integer,
        'win_rate', public.analytics_numeric_near((v_mode_v1->>'win_rate')::numeric, (v_mode_v2->>'win_rate')::numeric, 0.00000001)
          or ((v_mode_v1->>'win_rate') is null and (v_mode_v2->>'win_rate') is null),
        'profit_factor', public.analytics_numeric_near((v_mode_v1->>'profit_factor')::numeric, (v_mode_v2->>'profit_factor')::numeric, 0.00000001)
          or ((v_mode_v1->>'profit_factor') is null and (v_mode_v2->>'profit_factor') is null),
        'average_winner', public.analytics_numeric_near((v_mode_v1->>'average_winner')::numeric, (v_mode_v2->>'average_winner')::numeric, 0.00000001)
          or ((v_mode_v1->>'average_winner') is null and (v_mode_v2->>'average_winner') is null),
        'average_loser', public.analytics_numeric_near((v_mode_v1->>'average_loser')::numeric, (v_mode_v2->>'average_loser')::numeric, 0.00000001)
          or ((v_mode_v1->>'average_loser') is null and (v_mode_v2->>'average_loser') is null),
        'profit_per_trade', public.analytics_numeric_near((v_mode_v1->>'profit_per_trade')::numeric, (v_mode_v2->>'profit_per_trade')::numeric, 0.00000001)
          or ((v_mode_v1->>'profit_per_trade') is null and (v_mode_v2->>'profit_per_trade') is null),
        'biggest_win', public.analytics_numeric_near((v_mode_v1->>'biggest_win')::numeric, (v_mode_v2->>'biggest_win')::numeric, 0.00000001),
        'biggest_loss', public.analytics_numeric_near((v_mode_v1->>'biggest_loss')::numeric, (v_mode_v2->>'biggest_loss')::numeric, 0.00000001)
          or ((v_mode_v1->>'biggest_loss') is null and (v_mode_v2->>'biggest_loss') is null),
        'long_trades', (v_mode_v1->>'long_trades')::integer = (v_mode_v2->>'long_trades')::integer,
        'max_win_streak', (v_mode_v1->>'max_win_streak')::integer = (v_mode_v2->>'max_win_streak')::integer,
        'max_loss_streak', (v_mode_v1->>'max_loss_streak')::integer = (v_mode_v2->>'max_loss_streak')::integer,
        'current_equity', public.analytics_numeric_near((v_mode_v1->>'current_equity')::numeric, (v_mode_v2->>'current_equity')::numeric, 0.00000001),
        'session_total', (v_mode_v1->>'session_total')::integer = (v_mode_v2->>'session_total')::integer
      );
      if not (
        (v_parity->>'filtered_trade_count')::boolean
        and (v_parity->>'win_rate')::boolean
        and (v_parity->>'profit_factor')::boolean
        and (v_parity->>'long_trades')::boolean
        and (v_parity->>'max_win_streak')::boolean
        and (v_parity->>'max_loss_streak')::boolean
      ) then
        v_all_additive := false;
      end if;
    end if;

    v_raw_parity := public.profile_public_daily_stats_raw_parity(p_profile_id, v_mode);

    v_modes := v_modes || jsonb_build_object(
      v_mode,
      v_parity || jsonb_build_object('daily_stats_raw_parity', v_raw_parity->'parity')
    );
  end loop;

  return jsonb_build_object(
    'profile_id', p_profile_id,
    'viewer_id', p_viewer_id,
    'v1_meta', v_v1->'meta',
    'v2_meta', v_v2->'meta',
    'modes', v_modes,
    'parity_all_modes', v_all_additive,
    'all_mode_daily_stats_raw_parity', public.profile_public_daily_stats_raw_parity(p_profile_id, 'all')
  );
end;
$$;

create or replace function public.profile_analytics_v2_perf_probe(p_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_t0 timestamptz;
  v_t1 timestamptz;
  v_v1 jsonb;
  v_v2 jsonb;
  v_v1_ms numeric;
  v_v2_ms numeric;
begin
  v_t0 := clock_timestamp();
  v_v1 := public.rpc_v1_profile_statistics_bootstrap(p_profile_id);
  v_t1 := clock_timestamp();
  v_v1_ms := round(extract(epoch from (v_t1 - v_t0)) * 1000, 3);

  v_t0 := clock_timestamp();
  v_v2 := public.rpc_v1_profile_analytics_bootstrap_v2(p_profile_id);
  v_t1 := clock_timestamp();
  v_v2_ms := round(extract(epoch from (v_t1 - v_t0)) * 1000, 3);

  return jsonb_build_object(
    'profile_id', p_profile_id,
    'v1_elapsed_ms', v_v1_ms,
    'v2_elapsed_ms', v_v2_ms,
    'v1_bytes', octet_length(v_v1::text),
    'v2_bytes', octet_length(v_v2::text),
    'note', 'Single-sample probe only — not a general performance claim.'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS — no direct client access to public aggregate tables
-- ---------------------------------------------------------------------------

alter table public.trade_public_daily_stats enable row level security;
alter table public.profile_public_analytics_state enable row level security;

-- No SELECT/INSERT/UPDATE policies for authenticated/anon — maintenance via SECURITY DEFINER only.

revoke all on table public.trade_public_daily_stats from public, anon, authenticated;
revoke all on table public.profile_public_analytics_state from public, anon, authenticated;
grant select, insert, update, delete on table public.trade_public_daily_stats to service_role;
grant select, insert, update, delete on table public.profile_public_analytics_state to service_role;

-- ---------------------------------------------------------------------------
-- EXECUTE grants
-- ---------------------------------------------------------------------------

revoke all on function public.analytics_bump_profile_public_revision(uuid) from public, anon, authenticated;
grant execute on function public.analytics_bump_profile_public_revision(uuid) to service_role;

revoke all on function public.rebuild_trade_public_daily_stats_for_user(uuid, boolean) from public, anon, authenticated;
grant execute on function public.rebuild_trade_public_daily_stats_for_user(uuid, boolean) to service_role;

revoke all on function public.rebuild_trade_public_daily_stats_for_account(uuid, uuid, boolean) from public, anon, authenticated;
grant execute on function public.rebuild_trade_public_daily_stats_for_account(uuid, uuid, boolean) to service_role;

revoke all on function public.backfill_trade_public_daily_stats_batch(integer) from public, anon, authenticated;
grant execute on function public.backfill_trade_public_daily_stats_batch(integer) to service_role;

revoke all on function public.rebuild_trade_public_daily_stats_all_users() from public, anon, authenticated;
grant execute on function public.rebuild_trade_public_daily_stats_all_users() to service_role;

revoke all on function public.profile_public_daily_stats_mode_rollup(uuid, text) from public, anon, authenticated;
grant execute on function public.profile_public_daily_stats_mode_rollup(uuid, text) to service_role;

revoke all on function public.profile_public_daily_stats_raw_parity(uuid, text) from public, anon, authenticated;
grant execute on function public.profile_public_daily_stats_raw_parity(uuid, text) to service_role;

revoke all on function public.profile_analytics_v2_shadow_compare(uuid, uuid) from public, anon, authenticated;
grant execute on function public.profile_analytics_v2_shadow_compare(uuid, uuid) to service_role;

revoke all on function public.profile_analytics_v2_perf_probe(uuid) from public, anon, authenticated;
grant execute on function public.profile_analytics_v2_perf_probe(uuid) to service_role;

revoke all on function public.profile_viewer_can_view_trades(uuid) from public;
grant execute on function public.profile_viewer_can_view_trades(uuid) to authenticated, anon;

revoke all on function public.rpc_v1_profile_public_analytics_revision(uuid) from public;
grant execute on function public.rpc_v1_profile_public_analytics_revision(uuid) to authenticated;
grant execute on function public.rpc_v1_profile_public_analytics_revision(uuid) to anon;

revoke all on function public.rpc_v1_profile_analytics_bootstrap_v2(uuid) from public;
grant execute on function public.rpc_v1_profile_analytics_bootstrap_v2(uuid) to authenticated;
grant execute on function public.rpc_v1_profile_analytics_bootstrap_v2(uuid) to anon;

-- ---------------------------------------------------------------------------
-- Initial backfill (idempotent)
-- ---------------------------------------------------------------------------

do $migrate$
begin
  perform public.rebuild_trade_public_daily_stats_all_users();
exception
  when others then
    raise notice 'trade_public_daily_stats backfill skipped: %', sqlerrm;
end;
$migrate$;
