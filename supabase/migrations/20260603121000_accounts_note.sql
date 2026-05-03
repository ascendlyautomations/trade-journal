-- Optional per-account label in Input Settings (e.g. blown, passed).
alter table public.accounts
  add column if not exists note text;
