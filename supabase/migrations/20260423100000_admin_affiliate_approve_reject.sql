-- Approve/reject hooks for admin UI: required Stripe promo, optional code override, reject notes.

alter table public.affiliate_applications add column if not exists admin_notes text;

-- Replaced by admin_affiliate_approve (required promo + optional code).
drop function if exists public.admin_affiliate_approve_workflow(uuid);

create or replace function public.admin_affiliate_approve(
  p_application_id uuid,
  p_admin_code text,
  p_stripe_promo text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_uid uuid := auth.uid();
  app record;
  final_code text;
  base_name text;
  candidate text;
  attempt int := 0;
  promo text := nullif(trim(coalesce(p_stripe_promo, '')), '');
begin
  if admin_uid is null or not exists (select 1 from public.admin_users au where au.user_id = admin_uid) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  if promo is null then
    raise exception 'Stripe promo code ID is required';
  end if;

  select * into app from public.affiliate_applications where id = p_application_id for update;
  if not found then
    raise exception 'application not found';
  end if;
  if app.status <> 'pending' then
    raise exception 'application is not pending';
  end if;

  if nullif(trim(coalesce(p_admin_code, '')), '') is not null then
    final_code := upper(trim(p_admin_code));
    if exists (
      select 1 from public.affiliates a
      where lower(trim(a.code)) = lower(final_code) and a.user_id <> app.user_id
    ) then
      raise exception 'affiliate code already taken';
    end if;
  elsif nullif(trim(coalesce(app.requested_code, '')), '') is not null then
    final_code := upper(trim(app.requested_code));
    if exists (
      select 1 from public.affiliates a
      where lower(trim(a.code)) = lower(final_code) and a.user_id <> app.user_id
    ) then
      raise exception 'affiliate code already taken';
    end if;
  else
    select coalesce(nullif(trim(username), ''), 'AFF') into base_name from public.profiles where id = app.user_id;
    base_name := upper(regexp_replace(coalesce(base_name, 'AFF'), '[^a-zA-Z0-9]', '', 'g'));
    if length(base_name) < 1 then base_name := 'AFF'; end if;
    base_name := left(base_name, 20);

    loop
      attempt := attempt + 1;
      exit when attempt > 100;
      candidate := base_name || lpad(((floor(random() * 1000))::int % 1000)::text, 3, '0');
      if not exists (
        select 1 from public.affiliates a where lower(trim(a.code)) = lower(candidate)
      ) then
        final_code := candidate;
        exit;
      end if;
    end loop;

    if final_code is null then
      raise exception 'could not generate unique affiliate code';
    end if;
  end if;

  insert into public.affiliates (user_id, code, stripe_promo_code_id, updated_at)
  values (app.user_id, final_code, promo, now())
  on conflict (user_id) do update set
    code = excluded.code,
    stripe_promo_code_id = excluded.stripe_promo_code_id,
    updated_at = now();

  update public.profiles
  set referral_code = final_code
  where id = app.user_id;

  update public.affiliate_applications
  set
    status = 'approved',
    reviewed_at = now(),
    reviewed_by = admin_uid
  where id = p_application_id;

  return jsonb_build_object('ok', true, 'code', final_code);
end;
$$;

revoke all on function public.admin_affiliate_approve(uuid, text, text) from public;
grant execute on function public.admin_affiliate_approve(uuid, text, text) to authenticated;

create or replace function public.admin_affiliate_reject(
  p_application_id uuid,
  p_admin_notes text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_uid uuid := auth.uid();
  st text;
begin
  if admin_uid is null or not exists (select 1 from public.admin_users au where au.user_id = admin_uid) then
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
    reviewed_at = now(),
    reviewed_by = admin_uid,
    admin_notes = nullif(trim(coalesce(p_admin_notes, '')), '')
  where id = p_application_id;
end;
$$;

revoke all on function public.admin_affiliate_reject(uuid, text) from public;
grant execute on function public.admin_affiliate_reject(uuid, text) to authenticated;
