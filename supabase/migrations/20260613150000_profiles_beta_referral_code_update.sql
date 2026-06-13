-- Beta referral code: TRAXBETA10302 (replaces TRAXBETA).

create or replace function public.profiles_apply_beta_from_referred_by()
returns trigger
language plpgsql
as $$
begin
  if upper(trim(coalesce(new.referred_by, ''))) = 'TRAXBETA10302' then
    new.is_beta_tester := true;
    new.is_pro := true;
  end if;
  return new;
end;
$$;

comment on function public.profiles_apply_beta_from_referred_by() is
  'Sets is_beta_tester and is_pro when referred_by matches TRAXBETA10302. Does not unset either flag.';
