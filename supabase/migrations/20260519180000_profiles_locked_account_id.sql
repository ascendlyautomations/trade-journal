alter table public.profiles
  add column if not exists locked_account_id text;

comment on column public.profiles.locked_account_id is
  'Free plan: first account_id used for manual trading, enforced for later trade saves.';
