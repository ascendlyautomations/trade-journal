-- Daily trader psychology / lifestyle check-in — one row per user per Eastern trade date.
-- Correlates with trades via (user_id, check_in_date) ↔ (user_id, trade_date).

create table if not exists public.trader_daily_check_ins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  check_in_date date not null,
  sleep_hours numeric(4, 1),
  sleep_quality smallint,
  morning_rating smallint,
  stress_level smallint,
  energy_level smallint,
  focus_level smallint,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint trader_daily_check_ins_user_date_key unique (user_id, check_in_date),
  constraint trader_daily_check_ins_sleep_hours_check
    check (sleep_hours is null or (sleep_hours >= 0 and sleep_hours <= 24)),
  constraint trader_daily_check_ins_sleep_quality_check
    check (sleep_quality is null or sleep_quality between 1 and 5),
  constraint trader_daily_check_ins_morning_rating_check
    check (morning_rating is null or morning_rating between 1 and 5),
  constraint trader_daily_check_ins_stress_level_check
    check (stress_level is null or stress_level between 1 and 5),
  constraint trader_daily_check_ins_energy_level_check
    check (energy_level is null or energy_level between 1 and 5),
  constraint trader_daily_check_ins_focus_level_check
    check (focus_level is null or focus_level between 1 and 5)
);

create index if not exists trader_daily_check_ins_user_date_idx
  on public.trader_daily_check_ins (user_id, check_in_date desc);

comment on table public.trader_daily_check_ins is
  'Owner-only daily lifestyle / mental-state check-in. One row per user per Eastern trade date. Not exposed on public profiles or feeds.';

comment on column public.trader_daily_check_ins.check_in_date is
  'Eastern (America/New_York) calendar date — same semantics as trades.trade_date.';

create or replace function public.trader_daily_check_ins_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trader_daily_check_ins_set_updated_at_trigger
  on public.trader_daily_check_ins;
create trigger trader_daily_check_ins_set_updated_at_trigger
  before update on public.trader_daily_check_ins
  for each row
  execute function public.trader_daily_check_ins_set_updated_at();

alter table public.trader_daily_check_ins enable row level security;

drop policy if exists trader_daily_check_ins_select_own on public.trader_daily_check_ins;
create policy trader_daily_check_ins_select_own
  on public.trader_daily_check_ins
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists trader_daily_check_ins_insert_own on public.trader_daily_check_ins;
create policy trader_daily_check_ins_insert_own
  on public.trader_daily_check_ins
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists trader_daily_check_ins_update_own on public.trader_daily_check_ins;
create policy trader_daily_check_ins_update_own
  on public.trader_daily_check_ins
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists trader_daily_check_ins_delete_own on public.trader_daily_check_ins;
create policy trader_daily_check_ins_delete_own
  on public.trader_daily_check_ins
  for delete
  to authenticated
  using (user_id = auth.uid());

-- Realtime incremental updates for the signed-in user's check-ins.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'trader_daily_check_ins'
    ) then
      alter publication supabase_realtime add table public.trader_daily_check_ins;
    end if;
  end if;
end;
$$;
