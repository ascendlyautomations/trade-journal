-- Atomic affiliate approval: validate code → affiliates upsert → profile referral_code → application approved.

create or replace function public.admin_affiliate_approve_workflow(p_application_id uuid)
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
begin
  if admin_uid is null or not exists (select 1 from public.admin_users au where au.user_id = admin_uid) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  select * into app from public.affiliate_applications where id = p_application_id for update;
  if not found then
    raise exception 'application not found';
  end if;
  if app.status <> 'pending' then
    raise exception 'application is not pending';
  end if;

  if nullif(trim(coalesce(app.requested_code, '')), '') is not null then
    final_code := upper(trim(app.requested_code));
    if exists (
      select 1 from public.affiliates a
      where lower(trim(a.code)) = lower(final_code) and a.user_id <> app.user_id
    ) then
      raise exception 'affiliate code already taken' using errcode = '23514';
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
  values (app.user_id, final_code, null, now())
  on conflict (user_id) do update set
    code = excluded.code,
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

revoke all on function public.admin_affiliate_approve_workflow(uuid) from public;
grant execute on function public.admin_affiliate_approve_workflow(uuid) to authenticated;
