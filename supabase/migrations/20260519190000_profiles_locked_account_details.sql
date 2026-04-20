alter table public.profiles
  add column if not exists locked_account_type text,
  add column if not exists locked_account_size text,
  add column if not exists locked_account_name text,
  add column if not exists locked_account_number text;

comment on column public.profiles.locked_account_type is
  'Free plan lock: first manual account type used by user.';
comment on column public.profiles.locked_account_size is
  'Free plan lock: first manual account size used by user.';
comment on column public.profiles.locked_account_name is
  'Free plan lock: first manual account name used by user.';
comment on column public.profiles.locked_account_number is
  'Free plan lock: first manual account number/id used by user.';
