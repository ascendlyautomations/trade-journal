-- Evaluation preference: whether trades before the first saved rule revision use current rules.
alter table public.trading_preferences
  add column if not exists apply_rules_to_past_trades boolean not null default true;

-- Existing users keep revision-only scoring until they opt in.
update public.trading_preferences
set apply_rules_to_past_trades = false
where apply_rules_to_past_trades = true;

comment on column public.trading_preferences.apply_rules_to_past_trades is
  'When true, trades before the first saved rule revision are evaluated against current global rules.';
