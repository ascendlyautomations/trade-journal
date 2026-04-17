-- Aggregated affiliate application counts for admin dashboard (JSON).

create or replace function public.admin_affiliate_application_counts()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  p bigint;
  a bigint;
  r bigint;
  t bigint;
begin
  if uid is null or not exists (select 1 from public.admin_users au where au.user_id = uid) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  select
    count(*) filter (where status = 'pending'),
    count(*) filter (where status = 'approved'),
    count(*) filter (where status = 'rejected'),
    count(*)
  into p, a, r, t
  from public.affiliate_applications;

  return jsonb_build_object(
    'pending', coalesce(p, 0),
    'approved', coalesce(a, 0),
    'rejected', coalesce(r, 0),
    'total', coalesce(t, 0)
  );
end;
$$;

revoke all on function public.admin_affiliate_application_counts() from public;
grant execute on function public.admin_affiliate_application_counts() to authenticated;
