-- APNs device token registrations for Capacitor iOS push.
-- One row per physical device token; reassignment on login updates user_id.

create table if not exists public.device_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  platform text not null default 'ios'
    check (platform = 'ios'),
  device_token text not null,
  app_version text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  constraint device_push_tokens_device_token_key unique (device_token)
);

comment on table public.device_push_tokens is
  'Capacitor iOS APNs device tokens. Multiple devices per user; one user per token.';

create index if not exists device_push_tokens_user_id_idx
  on public.device_push_tokens (user_id);

create index if not exists device_push_tokens_user_platform_idx
  on public.device_push_tokens (user_id, platform);

alter table public.device_push_tokens enable row level security;

drop policy if exists device_push_tokens_select_own on public.device_push_tokens;
create policy device_push_tokens_select_own
  on public.device_push_tokens
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists device_push_tokens_insert_own on public.device_push_tokens;
create policy device_push_tokens_insert_own
  on public.device_push_tokens
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists device_push_tokens_update_own on public.device_push_tokens;
create policy device_push_tokens_update_own
  on public.device_push_tokens
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists device_push_tokens_delete_own on public.device_push_tokens;
create policy device_push_tokens_delete_own
  on public.device_push_tokens
  for delete
  to authenticated
  using (user_id = auth.uid());

-- Service role (push sender / register API) bypasses RLS.
revoke all on table public.device_push_tokens from anon;
grant select, insert, update, delete on table public.device_push_tokens to authenticated;
grant all on table public.device_push_tokens to service_role;
