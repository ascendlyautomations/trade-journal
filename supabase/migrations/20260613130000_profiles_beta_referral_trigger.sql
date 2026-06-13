-- Beta Tester V1: designated referral codes set profiles.is_beta_tester via referred_by.
-- Reuses existing ?ref= → localStorage → profiles.referred_by flow. Never auto-clears the flag.

create or replace function public.profiles_apply_beta_from_referred_by()
returns trigger
language plpgsql
as $$
begin
  if upper(trim(coalesce(new.referred_by, ''))) = 'TRAXBETA' then
    new.is_beta_tester := true;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_beta_referral_trigger on public.profiles;

create trigger profiles_beta_referral_trigger
  before insert or update of referred_by on public.profiles
  for each row
  execute function public.profiles_apply_beta_from_referred_by();

comment on function public.profiles_apply_beta_from_referred_by() is
  'Sets is_beta_tester when referred_by matches a designated beta referral code (e.g. TRAXBETA). Does not unset.';
