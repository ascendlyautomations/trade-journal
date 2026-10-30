-- Minimal extras for feed RLS block-peers isolated tests (not production).

create table if not exists public.admin_users (
  user_id uuid primary key
);

create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  image_url text,
  created_at timestamptz not null default now()
);

alter table public.stories enable row level security;

create or replace function public.users_have_active_block(p_user_a uuid, p_user_b uuid)
returns boolean
language sql
stable
security definer
set search_path to public
as $$
  select exists (
    select 1
    from public.user_blocks ub
    where (ub.blocker_id = p_user_a and ub.blocked_id = p_user_b)
       or (ub.blocker_id = p_user_b and ub.blocked_id = p_user_a)
  );
$$;

-- Production-shaped definer peer list (overrides benchmark invoker stub).
create or replace function public.get_active_block_peer_ids()
returns uuid[]
language sql
stable
security definer
set search_path to public
as $$
  select coalesce(array_agg(distinct peer_id), '{}'::uuid[])
  from (
    select ub.blocked_id as peer_id
    from public.user_blocks ub
    where ub.blocker_id = auth.uid()
    union
    select ub.blocker_id as peer_id
    from public.user_blocks ub
    where ub.blocked_id = auth.uid()
  ) peers
  where peer_id is not null;
$$;

grant execute on function public.users_have_active_block(uuid, uuid) to authenticated;

-- Production: guests read public profiles for post visibility EXISTS checks (no block restrictive on anon).
create policy profiles_select_public_discovery on public.profiles
  for select
  to anon
  using (coalesce(is_private, false) = false);
