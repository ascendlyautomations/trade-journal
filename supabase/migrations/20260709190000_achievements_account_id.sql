-- Link achievements to trading accounts (same FK pattern as trades.account_id).
alter table public.achievements
  add column if not exists account_id uuid references public.accounts (id) on delete set null;

create index if not exists achievements_account_id_idx
  on public.achievements (account_id)
  where account_id is not null;

comment on column public.achievements.account_id is
  'Trading account this achievement is associated with.';
