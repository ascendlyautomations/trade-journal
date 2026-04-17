-- Ban fields on profiles, admin audit log, admin-only RPCs (SECURITY DEFINER + admin_users gate).

alter table public.profiles
  add column if not exists is_banned boolean not null default false;

alter table public.profiles
  add column if not exists banned_reason text;

alter table public.profiles
  add column if not exists banned_at timestamptz;

alter table public.profiles
  add column if not exists banned_by uuid;

alter table public.profiles
  add column if not exists created_at timestamptz default now();

update public.profiles
set created_at = coalesce(created_at, now())
where created_at is null;

create table if not exists public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  admin_user_id uuid not null references auth.users (id) on delete cascade,
  target_user_id uuid references auth.users (id) on delete set null,
  action text not null,
  target_type text,
  target_id uuid,
  details jsonb,
  created_at timestamptz not null default now()
);

create index if not exists admin_audit_log_created_at_idx
  on public.admin_audit_log (created_at desc);

alter table public.admin_audit_log enable row level security;

drop policy if exists "admin_audit_log_select_admins" on public.admin_audit_log;
drop policy if exists "admin_audit_log_insert_admins" on public.admin_audit_log;

create policy "admin_audit_log_select_admins"
  on public.admin_audit_log for select to authenticated
  using (
    exists (select 1 from public.admin_users au where au.user_id = auth.uid())
  );

create policy "admin_audit_log_insert_admins"
  on public.admin_audit_log for insert to authenticated
  with check (
    exists (select 1 from public.admin_users au where au.user_id = auth.uid())
      and admin_user_id = auth.uid()
  );

-- Admins may update any profile (moderation). Coexists with normal "update own" policies via OR.
drop policy if exists "profiles_admin_update" on public.profiles;
create policy "profiles_admin_update"
  on public.profiles for update to authenticated
  using (exists (select 1 from public.admin_users au where au.user_id = auth.uid()))
  with check (exists (select 1 from public.admin_users au where au.user_id = auth.uid()));

-- ---------------------------------------------------------------------------
-- admin_is_current_user_admin: lightweight gate for clients if needed
-- ---------------------------------------------------------------------------
create or replace function public.admin_is_current_user_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admin_users au where au.user_id = auth.uid());
$$;

revoke all on function public.admin_is_current_user_admin() from public;
grant execute on function public.admin_is_current_user_admin() to authenticated;

-- ---------------------------------------------------------------------------
-- admin_analytics_bundle: aggregate metrics + daily series (UTC days)
-- ---------------------------------------------------------------------------
create or replace function public.admin_analytics_bundle(p_series_days int default 14)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  day_start timestamptz := date_trunc('day', timezone('utc', now()));
  week_start timestamptz := day_start - interval '6 days';
  day24 timestamptz := timezone('utc', now()) - interval '24 hours';
  week7 timestamptz := timezone('utc', now()) - interval '7 days';
  series_from timestamptz := day_start - (greatest(1, least(p_series_days, 90))::int - 1) * interval '1 day';
begin
  if uid is null or not exists (select 1 from public.admin_users au where au.user_id = uid) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'total_users', (select count(*)::bigint from public.profiles),
    'new_users_today', (
      select count(*)::bigint from public.profiles p
      where coalesce(p.created_at, now()) >= day_start
    ),
    'new_users_this_week', (
      select count(*)::bigint from public.profiles p
      where coalesce(p.created_at, now()) >= week_start
    ),
    'dau_users_24h', (
      select count(*)::bigint from (
        select distinct t.user_id from public.trades t where t.created_at >= day24
        union
        select distinct po.user_id from public.posts po where po.created_at >= day24
        union
        select distinct pp.user_id from public.profile_posts pp where pp.created_at >= day24
        union
        select distinct s.user_id from public.stories s where s.created_at >= day24
        union
        select distinct f.user_id from public.feedback_submissions f where f.created_at >= day24
        union
        select distinct st.user_id from public.support_tickets st where st.created_at >= day24
      ) x
    ),
    'wau_users_7d', (
      select count(*)::bigint from (
        select distinct t.user_id from public.trades t where t.created_at >= week7
        union
        select distinct po.user_id from public.posts po where po.created_at >= week7
        union
        select distinct pp.user_id from public.profile_posts pp where pp.created_at >= week7
        union
        select distinct s.user_id from public.stories s where s.created_at >= week7
        union
        select distinct f.user_id from public.feedback_submissions f where f.created_at >= week7
        union
        select distinct st.user_id from public.support_tickets st where st.created_at >= week7
      ) y
    ),
    'trades_logged_today', (
      select count(*)::bigint from public.trades t where t.created_at >= day_start
    ),
    'trades_logged_this_week', (
      select count(*)::bigint from public.trades t where t.created_at >= week_start
    ),
    'posts_created_today', (
      select count(*)::bigint from public.posts p where p.created_at >= day_start
    ),
    'posts_created_this_week', (
      select count(*)::bigint from public.posts p where p.created_at >= week_start
    ),
    'total_trades', (select count(*)::bigint from public.trades),
    'total_posts', (select count(*)::bigint from public.posts),
    'total_feedback', (select count(*)::bigint from public.feedback_submissions),
    'total_support_tickets', (select count(*)::bigint from public.support_tickets),
    'open_support_tickets', (
      select count(*)::bigint from public.support_tickets s
      where lower(trim(coalesce(s.status, 'open'))) = 'open'
    ),
    'open_feedback_items', (
      select count(*)::bigint from public.feedback_submissions f
      where lower(trim(coalesce(f.status, 'open'))) = 'open'
    ),
    'banned_users', (
      select count(*)::bigint from public.profiles p where coalesce(p.is_banned, false) = true
    ),
    'series_days', greatest(1, least(p_series_days, 90)),
    'series_new_users', coalesce((
      select jsonb_agg(jsonb_build_object('day', d::text, 'count', c) order by d)
      from (
        select date_trunc('day', timezone('utc', coalesce(p.created_at, now())))::date as d,
               count(*)::bigint as c
        from public.profiles p
        where coalesce(p.created_at, now()) >= series_from
        group by 1
      ) s
    ), '[]'::jsonb),
    'series_trades', coalesce((
      select jsonb_agg(jsonb_build_object('day', d::text, 'count', c) order by d)
      from (
        select date_trunc('day', timezone('utc', t.created_at))::date as d,
               count(*)::bigint as c
        from public.trades t
        where t.created_at >= series_from
        group by 1
      ) s
    ), '[]'::jsonb),
    'series_posts', coalesce((
      select jsonb_agg(jsonb_build_object('day', d::text, 'count', c) order by d)
      from (
        select date_trunc('day', timezone('utc', p.created_at))::date as d,
               count(*)::bigint as c
        from public.posts p
        where p.created_at >= series_from
        group by 1
      ) s
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.admin_analytics_bundle(int) from public;
grant execute on function public.admin_analytics_bundle(int) to authenticated;

-- ---------------------------------------------------------------------------
-- admin_list_users: directory search + filters (email from auth.users)
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_users(
  p_search text default null,
  p_banned text default 'all',
  p_pro text default 'all',
  p_private text default 'all',
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
    count(*) over ()::bigint as full_count
  from public.profiles p
  left join auth.users u on u.id = p.id
  where
    (q is null or p.username ilike '%' || q || '%' or coalesce(p.name, '') ilike '%' || q || '%'
      or coalesce(u.email, '') ilike '%' || q || '%')
    and (
      lower(trim(coalesce(p_banned, 'all'))) = 'all'
      or (lower(trim(p_banned)) = 'banned' and coalesce(p.is_banned, false) = true)
      or (lower(trim(p_banned)) = 'active' and coalesce(p.is_banned, false) = false)
    )
    and (
      lower(trim(coalesce(p_pro, 'all'))) = 'all'
      or (
        lower(trim(p_pro)) = 'pro'
        and (
          coalesce(p.is_pro, false) = true
          or lower(trim(coalesce(p.subscription_status, ''))) in ('active', 'trialing')
        )
      )
      or (
        lower(trim(p_pro)) = 'non_pro'
        and coalesce(p.is_pro, false) = false
        and lower(trim(coalesce(p.subscription_status, ''))) not in ('active', 'trialing')
      )
    )
    and (
      lower(trim(coalesce(p_private, 'all'))) = 'all'
      or (lower(trim(p_private)) = 'private' and coalesce(p.is_private, false) = true)
      or (lower(trim(p_private)) = 'public' and coalesce(p.is_private, false) = false)
    )
  order by coalesce(p.created_at, now()) desc
  limit lim
  offset off;
end;
$$;

revoke all on function public.admin_list_users(text, text, text, text, int, int) from public;
grant execute on function public.admin_list_users(text, text, text, text, int, int) to authenticated;

-- ---------------------------------------------------------------------------
-- admin_recent_audit: compact feed for dashboard
-- ---------------------------------------------------------------------------
create or replace function public.admin_recent_audit(p_limit int default 12)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
  lim int := greatest(1, least(coalesce(p_limit, 12), 50));
begin
  if uid is null or not exists (select 1 from public.admin_users au where au.user_id = uid) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', a.id,
        'admin_user_id', a.admin_user_id,
        'admin_email', ae.email,
        'target_user_id', a.target_user_id,
        'target_email', te.email,
        'action', a.action,
        'target_type', a.target_type,
        'target_id', a.target_id,
        'details', a.details,
        'created_at', a.created_at
      )
      order by a.created_at desc
    )
    from (
      select *
      from public.admin_audit_log
      order by created_at desc
      limit lim
    ) a
    left join auth.users ae on ae.id = a.admin_user_id
    left join auth.users te on te.id = a.target_user_id
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_recent_audit(int) from public;
grant execute on function public.admin_recent_audit(int) to authenticated;

-- Head counts for another user (user detail modal) without widening client RLS on large tables.
create or replace function public.admin_user_activity_counts(p_target uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not exists (select 1 from public.admin_users au where au.user_id = auth.uid()) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'trades', (select count(*)::bigint from public.trades t where t.user_id = p_target),
    'posts', (select count(*)::bigint from public.posts p where p.user_id = p_target),
    'achievements', (select count(*)::bigint from public.achievements a where a.user_id = p_target)
  );
end;
$$;

revoke all on function public.admin_user_activity_counts(uuid) from public;
grant execute on function public.admin_user_activity_counts(uuid) to authenticated;
