-- Restore automatic is_pro = true for every new profiles INSERT
-- (re-applies 20260917140000_profiles_signup_default_is_pro.sql).

alter table public.profiles
  alter column is_pro set default true;

comment on column public.profiles.is_pro is
  'Manual / comp TraxPro flag. Defaults true for new signups; Stripe and lifetime triggers may still adjust billing mirrors on update.';

create or replace function public.profiles_grant_pro_on_signup()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.is_pro := true;
  return new;
end;
$$;

comment on function public.profiles_grant_pro_on_signup() is
  'Ensures every new profiles row is created with is_pro = true.';

drop trigger if exists profiles_grant_pro_on_signup_trigger on public.profiles;

create trigger profiles_grant_pro_on_signup_trigger
  before insert on public.profiles
  for each row
  execute function public.profiles_grant_pro_on_signup();

comment on trigger profiles_grant_pro_on_signup_trigger on public.profiles is
  'Signup Pro grant — runs on insert before RLS-visible row is stored.';
