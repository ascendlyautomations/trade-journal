-- Achievement withdrawals can be labeled with a prop firm, same as ledger and cycle payouts.

alter table public.prop_firm_payout_assignments
  drop constraint if exists prop_firm_payout_assignments_key_check;

alter table public.prop_firm_payout_assignments
  add constraint prop_firm_payout_assignments_key_check
  check (payout_key ~ '^(ledger|cycle|achievement):[0-9a-fA-F-]{36}$');
