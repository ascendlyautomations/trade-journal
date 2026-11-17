-- Remembers whether the trader finished, skipped, or dismissed the
-- Trading Analytics Preferences invitation. A saved preferences row with
-- blank optional fields is still a completed setup; this table does not
-- infer completeness from those columns.

create table if not exists public.trading_preference_discovery (
  user_id uuid primary key references auth.users (id) on delete cascade,
  response text not null,
  updated_at timestamptz not null default now(),
  constraint trading_preference_discovery_response_check check (
    response in ('completed', 'skipped', 'dismissed')
  )
);

comment on table public.trading_preference_discovery is
  'Cross-device invitation state for Trading Analytics Preferences. completed, skipped, and dismissed are explicit responses.';

create or replace function public.trading_preference_discovery_touch()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.trading_preference_discovery_touch() from public, anon, authenticated;

drop trigger if exists trading_preference_discovery_touch
  on public.trading_preference_discovery;
create trigger trading_preference_discovery_touch
before update on public.trading_preference_discovery
for each row
execute function public.trading_preference_discovery_touch();

alter table public.trading_preference_discovery enable row level security;

drop policy if exists "trading_preference_discovery_select_own"
  on public.trading_preference_discovery;
create policy "trading_preference_discovery_select_own"
on public.trading_preference_discovery
for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "trading_preference_discovery_insert_own"
  on public.trading_preference_discovery;
create policy "trading_preference_discovery_insert_own"
on public.trading_preference_discovery
for insert
to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists "trading_preference_discovery_update_own"
  on public.trading_preference_discovery;
create policy "trading_preference_discovery_update_own"
on public.trading_preference_discovery
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

revoke all on table public.trading_preference_discovery from public, anon, authenticated;
grant select, insert, update on table public.trading_preference_discovery to authenticated;
grant select, insert, update, delete on table public.trading_preference_discovery to service_role;
