create table if not exists public.presets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  values jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.presets enable row level security;

drop policy if exists "presets_select_own" on public.presets;
create policy "presets_select_own"
  on public.presets
  for select
  using (auth.uid() = user_id);

drop policy if exists "presets_insert_own" on public.presets;
create policy "presets_insert_own"
  on public.presets
  for insert
  with check (auth.uid() = user_id);

drop policy if exists "presets_delete_own" on public.presets;
create policy "presets_delete_own"
  on public.presets
  for delete
  using (auth.uid() = user_id);
