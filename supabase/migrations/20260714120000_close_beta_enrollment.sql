-- Close public beta enrollment: stop TRAXBETA10302 from granting
-- is_beta_tester / is_pro. Existing rows with is_beta_tester = true are unchanged.
-- Privilege protect trigger already forbids client self-grants (no beta exception).

create or replace function public.profiles_apply_beta_from_referred_by()
returns trigger
language plpgsql
as $$
begin
  -- Beta signup closed — referral codes no longer grant beta or pro access.
  return new;
end;
$$;

comment on function public.profiles_apply_beta_from_referred_by() is
  'No-op: public beta enrollment closed. Existing is_beta_tester rows are preserved; referred_by no longer grants flags.';
