-- Prevent duplicate trading accounts from rapid double-submit (same user + account name).

create unique index if not exists accounts_user_id_name_unique_idx
  on public.accounts (user_id, lower(trim(name)));
