-- Phase 3: atomic manual ledger payout delete (entry + metadata-linked achievements only).

create or replace function public.delete_account_payout_entry(
  p_entry_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_owner_id uuid;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select e.user_id
  into v_owner_id
  from public.account_payout_entries e
  where e.id = p_entry_id
  for update;

  if not found then
    -- Idempotent: entry already deleted (safe retries).
    return;
  end if;

  if v_owner_id is distinct from v_user_id then
    raise exception 'permission denied' using errcode = '42501';
  end if;

  delete from public.achievements a
  where a.user_id = v_user_id
    and a.achievement_type in ('prop_firm_payout', 'live_trading_payout', 'payout')
    and a.metadata->>'account_payout_entry_id' = p_entry_id::text;

  delete from public.account_payout_entries e
  where e.id = p_entry_id
    and e.user_id = v_user_id;
end;
$$;

comment on function public.delete_account_payout_entry(uuid) is
  'Owner deletes one manual ledger withdrawal and achievements linked by metadata.account_payout_entry_id only.';

revoke all on function public.delete_account_payout_entry(uuid) from public;
grant execute on function public.delete_account_payout_entry(uuid) to authenticated;
