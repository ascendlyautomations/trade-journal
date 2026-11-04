-- Free-plan slot epoch columns are non-privileged; authenticated clients must read them
-- for modal gating (profiles uses column-level SELECT grants since 20261001073000).

grant select (
  free_plan_trade_slots_epoch,
  free_plan_trade_slots_confirmed_epoch
) on table public.profiles to anon, authenticated;
