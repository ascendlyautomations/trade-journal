alter table public.profiles
  add column if not exists has_used_csv_import boolean not null default false;

comment on column public.profiles.has_used_csv_import is
  'Free tier: first successful CSV import sets this true; Pro users ignore the limit.';
