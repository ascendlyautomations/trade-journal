alter table public.trades
  add column if not exists is_initial_import boolean not null default false;

comment on column public.trades.is_initial_import is
  'True for rows created via CSV bulk import (initial import); false for manual and other inserts.';
