-- Pause automatic TraxPro (is_pro) grants on new profile INSERT.
-- Reversible via supabase/rollbacks/20261007200000_profiles_signup_no_automatic_is_pro_rollback.sql
--
-- Does not UPDATE existing rows. Explicit is_pro := true (admin, creator redeem,
-- Stripe mirrors, etc.) on insert or update is unchanged.

drop trigger if exists profiles_grant_pro_on_signup_trigger on public.profiles;

alter table public.profiles
  alter column is_pro set default false;

comment on column public.profiles.is_pro is
  'Manual / comp TraxPro flag. New signups default false; subscriptions, admin grants, and explicit inserts may set true.';

create or replace function public.profiles_grant_pro_on_signup()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  -- Intentionally no-op while automatic signup Pro grants are paused.
  return new;
end;
$$;

comment on function public.profiles_grant_pro_on_signup() is
  'Paused: no longer forces is_pro on insert. Trigger remains dropped; function kept for rollback compatibility.';
