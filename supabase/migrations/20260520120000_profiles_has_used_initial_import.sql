alter table public.profiles
  add column if not exists has_used_initial_import boolean not null default false;

comment on column public.profiles.has_used_initial_import is
  'Set true after the user completes their first successful CSV import (client).';
