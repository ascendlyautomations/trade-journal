-- Affiliate applications workflow + admin approve/reject RPCs.

-- -----------------------------------------------------------------------------
-- affiliates (Stripe + public referral code)
-- -----------------------------------------------------------------------------
create table if not exists public.affiliates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  code text not null,
  stripe_promo_code_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint affiliates_user_id_key unique (user_id)
);

create unique index if not exists affiliates_code_lower_idx on public.affiliates (lower(trim(code)));

-- -----------------------------------------------------------------------------
-- affiliate_applications
-- -----------------------------------------------------------------------------
create table if not exists public.affiliate_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  email text,
  full_name text,
  social_handle text,
  platform text,
  audience_size text,
  why_join text,
  promo_plan text,
  status text not null default 'pending',
  requested_code text,
  approved_code text,
  admin_notes text,
  reviewed_by uuid references auth.users (id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint affiliate_applications_status_ck check (status in ('pending', 'approved', 'rejected'))
);

create index if not exists affiliate_applications_user_id_idx on public.affiliate_applications (user_id);
create index if not exists affiliate_applications_status_created_idx on public.affiliate_applications (status, created_at desc);

-- Legacy column migration (experience / why -> why_join)
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'affiliate_applications' and column_name = 'experience'
  ) then
    execute $e$
      update public.affiliate_applications
      set why_join = coalesce(nullif(trim(why_join), ''), nullif(trim(experience), ''))
      where (why_join is null or trim(why_join) = '') and experience is not null
    $e$;
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'affiliate_applications' and column_name = 'why'
  ) then
    execute $e$
      update public.affiliate_applications
      set why_join = coalesce(nullif(trim(why_join), ''), nullif(trim(why), ''))
      where (why_join is null or trim(why_join) = '') and why is not null
    $e$;
  end if;
end $$;

alter table public.affiliate_applications add column if not exists email text;
alter table public.affiliate_applications add column if not exists full_name text;
alter table public.affiliate_applications add column if not exists social_handle text;
alter table public.affiliate_applications add column if not exists platform text;
alter table public.affiliate_applications add column if not exists audience_size text;
alter table public.affiliate_applications add column if not exists why_join text;
alter table public.affiliate_applications add column if not exists promo_plan text;
alter table public.affiliate_applications add column if not exists requested_code text;
alter table public.affiliate_applications add column if not exists approved_code text;
alter table public.affiliate_applications add column if not exists admin_notes text;
alter table public.affiliate_applications add column if not exists reviewed_by uuid references auth.users (id) on delete set null;
alter table public.affiliate_applications add column if not exists reviewed_at timestamptz;

-- Only one pending application per user
create unique index if not exists affiliate_applications_one_pending_per_user
  on public.affiliate_applications (user_id)
  where status = 'pending';

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------
alter table public.affiliate_applications enable row level security;
alter table public.affiliates enable row level security;

drop policy if exists "affiliate_applications_select_own" on public.affiliate_applications;
drop policy if exists "affiliate_applications_insert_own" on public.affiliate_applications;
drop policy if exists "affiliate_applications_update_own_pending" on public.affiliate_applications;
drop policy if exists "affiliate_applications_select_admin" on public.affiliate_applications;

create policy "affiliate_applications_select_own"
  on public.affiliate_applications for select to authenticated
  using (user_id = auth.uid());

create policy "affiliate_applications_insert_own"
  on public.affiliate_applications for insert to authenticated
  with check (user_id = auth.uid());

create policy "affiliate_applications_update_own_pending"
  on public.affiliate_applications for update to authenticated
  using (user_id = auth.uid() and status = 'pending')
  with check (user_id = auth.uid() and status = 'pending');

create policy "affiliate_applications_select_admin"
  on public.affiliate_applications for select to authenticated
  using (exists (select 1 from public.admin_users au where au.user_id = auth.uid()));

drop policy if exists "affiliates_select_own" on public.affiliates;
drop policy if exists "affiliates_select_admin" on public.affiliates;

create policy "affiliates_select_own"
  on public.affiliates for select to authenticated
  using (user_id = auth.uid());

create policy "affiliates_select_admin"
  on public.affiliates for select to authenticated
  using (exists (select 1 from public.admin_users au where au.user_id = auth.uid()));

-- -----------------------------------------------------------------------------
-- Admin: approve (creates/updates affiliates + profile.referral_code + application row)
-- -----------------------------------------------------------------------------
create or replace function public.admin_affiliate_application_approve(
  p_application_id uuid,
  p_final_code text,
  p_stripe_promo_code_id text default null,
  p_admin_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  app record;
  code_clean text := upper(trim(coalesce(p_final_code, '')));
  promo_clean text := nullif(trim(coalesce(p_stripe_promo_code_id, '')), '');
begin
  if uid is null or not exists (select 1 from public.admin_users au where au.user_id = uid) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  if code_clean = '' then
    raise exception 'final_code required';
  end if;

  select * into app from public.affiliate_applications where id = p_application_id for update;
  if not found then
    raise exception 'application not found';
  end if;
  if app.status <> 'pending' then
    raise exception 'application is not pending';
  end if;

  if exists (
    select 1 from public.affiliates a
    where lower(trim(a.code)) = lower(code_clean) and a.user_id <> app.user_id
  ) then
    raise exception 'affiliate code already in use';
  end if;

  insert into public.affiliates (user_id, code, stripe_promo_code_id, updated_at)
  values (app.user_id, code_clean, promo_clean, now())
  on conflict (user_id) do update set
    code = excluded.code,
    stripe_promo_code_id = coalesce(excluded.stripe_promo_code_id, public.affiliates.stripe_promo_code_id),
    updated_at = now();

  update public.profiles
  set referral_code = code_clean
  where id = app.user_id;

  update public.affiliate_applications
  set
    status = 'approved',
    approved_code = code_clean,
    admin_notes = nullif(trim(coalesce(p_admin_notes, '')), ''),
    reviewed_by = uid,
    reviewed_at = now(),
    updated_at = now()
  where id = p_application_id;

  return jsonb_build_object('ok', true, 'user_id', app.user_id, 'code', code_clean);
end;
$$;

revoke all on function public.admin_affiliate_application_approve(uuid, text, text, text) from public;
grant execute on function public.admin_affiliate_application_approve(uuid, text, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Admin: reject
-- -----------------------------------------------------------------------------
create or replace function public.admin_affiliate_application_reject(
  p_application_id uuid,
  p_admin_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  st text;
begin
  if uid is null or not exists (select 1 from public.admin_users au where au.user_id = uid) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  select status into st from public.affiliate_applications where id = p_application_id for update;
  if not found then
    raise exception 'application not found';
  end if;
  if st <> 'pending' then
    raise exception 'application is not pending';
  end if;

  update public.affiliate_applications
  set
    status = 'rejected',
    admin_notes = nullif(trim(coalesce(p_admin_notes, '')), ''),
    reviewed_by = uid,
    reviewed_at = now(),
    updated_at = now()
  where id = p_application_id;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.admin_affiliate_application_reject(uuid, text) from public;
grant execute on function public.admin_affiliate_application_reject(uuid, text) to authenticated;
