-- Soft-hide accounts from pickers without deleting rows or breaking trade FKs.
alter table public.accounts
  add column if not exists is_active boolean not null default true;
