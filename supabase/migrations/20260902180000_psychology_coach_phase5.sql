-- Phase 5: post-trade reflection fields + owner-only psychology coach snapshot cache.

alter table public.trades
  add column if not exists exit_emotion text;

alter table public.trades
  add column if not exists execution_rating smallint;

alter table public.trades
  drop constraint if exists trades_execution_rating_check;

alter table public.trades
  add constraint trades_execution_rating_check
  check (execution_rating is null or execution_rating between 1 and 5);

comment on column public.trades.exit_emotion is
  'Owner-only emotion after trade exit — not exposed on public feeds.';

comment on column public.trades.execution_rating is
  'Owner-only execution/discipline rating 1–5 after trade — not exposed on public feeds.';

create table if not exists public.psychology_coach_snapshots (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  facts_hash text not null,
  summary_json jsonb not null default '{}'::jsonb,
  ai_explanation text,
  generated_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.psychology_coach_snapshots is
  'Owner-only cached psychology coach summaries keyed by deterministic facts hash.';

create or replace function public.psychology_coach_snapshots_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists psychology_coach_snapshots_set_updated_at_trigger
  on public.psychology_coach_snapshots;
create trigger psychology_coach_snapshots_set_updated_at_trigger
  before update on public.psychology_coach_snapshots
  for each row
  execute function public.psychology_coach_snapshots_set_updated_at();

alter table public.psychology_coach_snapshots enable row level security;

drop policy if exists psychology_coach_snapshots_select_own on public.psychology_coach_snapshots;
create policy psychology_coach_snapshots_select_own
  on public.psychology_coach_snapshots
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists psychology_coach_snapshots_insert_own on public.psychology_coach_snapshots;
create policy psychology_coach_snapshots_insert_own
  on public.psychology_coach_snapshots
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists psychology_coach_snapshots_update_own on public.psychology_coach_snapshots;
create policy psychology_coach_snapshots_update_own
  on public.psychology_coach_snapshots
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists psychology_coach_snapshots_delete_own on public.psychology_coach_snapshots;
create policy psychology_coach_snapshots_delete_own
  on public.psychology_coach_snapshots
  for delete
  to authenticated
  using (user_id = auth.uid());
