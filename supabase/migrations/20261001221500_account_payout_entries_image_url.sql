-- Owner screenshot on manual withdrawal rows (`account_payout_entries`).
-- Nullable. Public profile insights stay whitelisted and do not return this column.
-- Owner RLS on the row is unchanged.

alter table public.account_payout_entries
  add column if not exists image_url text null;

alter table public.account_payout_entries
  drop constraint if exists account_payout_entries_image_url_length;

alter table public.account_payout_entries
  add constraint account_payout_entries_image_url_length
  check (
    image_url is null
    or char_length(image_url) between 1 and 2048
  );

comment on column public.account_payout_entries.image_url is
  'Optional owner screenshot URL. Not included in rpc_v1_profile_account_insights.';
