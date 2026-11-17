-- Optional personal compliance target for Trading Rules Analytics (display/goal tracking only).
alter table public.trading_preferences
  add column if not exists personal_compliance_target_percent double precision null;

alter table public.trading_preferences
  drop constraint if exists trading_preferences_personal_compliance_target_check,
  add constraint trading_preferences_personal_compliance_target_check check (
    personal_compliance_target_percent is null
    or (personal_compliance_target_percent >= 0 and personal_compliance_target_percent <= 100)
  );

comment on column public.trading_preferences.personal_compliance_target_percent is
  'Optional personal rule compliance target (0–100). Informational; does not affect compliance checks.';
