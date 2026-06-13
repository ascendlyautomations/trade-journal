-- Beta Tester V1: flag on profiles (default false for all users).

alter table public.profiles
  add column if not exists is_beta_tester boolean not null default false;

comment on column public.profiles.is_beta_tester is
  'True when the user is a TradeTrax beta tester (e.g. redeemed a beta invite code).';

-- Explicit backfill for any rows created before the default was applied.
update public.profiles
set is_beta_tester = false
where is_beta_tester is distinct from false;

-- Admin directory: expose beta tester status.
drop function if exists public.admin_list_users(text, boolean, boolean, boolean, int, int);

create or replace function public.admin_list_users(
  p_search text default null,
  p_banned boolean default null,
  p_pro boolean default null,
  p_private boolean default null,
  p_limit int default 40,
  p_offset int default 0
)
returns table (
  id uuid,
  username text,
  name text,
  email text,
  avatar_url text,
  created_at timestamptz,
  is_private boolean,
  is_pro boolean,
  subscription_status text,
  referral_code text,
  is_banned boolean,
  banned_reason text,
  banned_at timestamptz,
  is_beta_tester boolean,
  full_count bigint
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
  lim int := greatest(1, least(coalesce(p_limit, 40), 100));
  off int := greatest(0, coalesce(p_offset, 0));
  q text := nullif(trim(coalesce(p_search, '')), '');
begin
  if uid is null or not exists (select 1 from public.admin_users au where au.user_id = uid) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  return query
  select
    p.id,
    p.username::text,
    coalesce(p.name, '')::text as name,
    coalesce(u.email, '')::text as email,
    p.avatar_url::text,
    coalesce(p.created_at, now()) as created_at,
    coalesce(p.is_private, false) as is_private,
    coalesce(p.is_pro, false) as is_pro,
    coalesce(p.subscription_status, '')::text as subscription_status,
    coalesce(p.referral_code, '')::text as referral_code,
    coalesce(p.is_banned, false) as is_banned,
    p.banned_reason::text,
    p.banned_at,
    coalesce(p.is_beta_tester, false) as is_beta_tester,
    count(*) over ()::bigint as full_count
  from public.profiles p
  left join auth.users u on u.id = p.id
  where
    (q is null or p.username ilike '%' || q || '%' or coalesce(p.name, '') ilike '%' || q || '%'
      or coalesce(u.email, '') ilike '%' || q || '%')
    and (
      p_banned is null
      or (p_banned = true and coalesce(p.is_banned, false) = true)
      or (p_banned = false and coalesce(p.is_banned, false) = false)
    )
    and (
      p_pro is null
      or (
        p_pro = true
        and (
          coalesce(p.is_pro, false) = true
          or lower(trim(coalesce(p.subscription_status, ''))) in ('active', 'trialing')
        )
      )
      or (
        p_pro = false
        and coalesce(p.is_pro, false) = false
        and lower(trim(coalesce(p.subscription_status, ''))) not in ('active', 'trialing')
      )
    )
    and (
      p_private is null
      or (p_private = true and coalesce(p.is_private, false) = true)
      or (p_private = false and coalesce(p.is_private, false) = false)
    )
  order by coalesce(p.created_at, now()) desc
  limit lim
  offset off;
end;
$$;

revoke all on function public.admin_list_users(text, boolean, boolean, boolean, int, int) from public;
grant execute on function public.admin_list_users(text, boolean, boolean, boolean, int, int) to authenticated;
