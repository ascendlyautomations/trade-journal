-- Manual authorization verification for account public insights.
-- NOT applied by the migration pipeline — run explicitly after deploying:
--   supabase/migrations/20260827220000_account_public_insights_dropdown_payouts.sql
--
-- Example (psql against staging):
--   \i supabase/verification/account_public_insights_authorization.sql
--
-- Creates temporary rows inside a transaction and rolls back on completion or failure.

begin;

do $$
declare
  v_owner uuid;
  v_other uuid;
  v_private_profile uuid;
  v_test_account_id uuid;
  v_test_payout_id uuid;
  v_payload jsonb;
begin
  select id into v_owner from auth.users limit 1;
  if v_owner is null then
    raise exception 'account_insights_verify: requires at least one auth.users row';
  end if;

  select id into v_other from auth.users where id <> v_owner limit 1;

  insert into public.accounts (user_id, name, account_size, mode, category, custom_public_status)
  values (v_owner, '__insights_verify__', '10000', 'Eval', 'Prop Firm', 'Passed')
  returning id into v_test_account_id;

  insert into public.account_payout_entries (account_id, user_id, amount, payout_date, note)
  values (v_test_account_id, v_owner, 100.00, current_date, 'public payout note')
  returning id into v_test_payout_id;

  -- Public-profile visibility (anon viewer: no JWT during psql unless set locally)
  if exists (
    select 1
    from public.profiles p
    where p.id = v_owner
      and coalesce(p.is_private, false) = false
  ) then
    v_payload := public.rpc_v1_profile_account_insights(v_owner::text);
    if coalesce(v_payload #>> '{meta,can_view}', 'false') <> 'true' then
      raise exception 'account_insights_verify: public profile can_view expected true';
    end if;

    if jsonb_array_length(coalesce(v_payload #> '{data,accounts}', '[]'::jsonb)) < 1 then
      raise exception 'account_insights_verify: expected account in RPC payload';
    end if;
  else
    raise notice 'account_insights_verify: public visibility skipped — owner profile is private';
  end if;

  -- Forbidden ACCOUNT-level fields (private accounts.note must not appear at account level)
  select public.rpc_v1_profile_account_insights(v_owner::text) into v_payload;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(v_payload #> '{data,accounts}', '[]'::jsonb)) elem
    where elem ?| array[
      'account_number',
      'can_add_trades',
      'show_in_account_dropdowns',
      'user_id',
      'note',
      'account_size',
      'is_active'
    ]
  ) then
    raise exception 'account_insights_verify: forbidden account-level fields in RPC payload';
  end if;

  -- Payout note is public; payout object must stay whitelisted
  if coalesce(v_payload #>> '{meta,can_view}', 'false') = 'true'
     and not exists (
    select 1
    from jsonb_array_elements(coalesce(v_payload #> '{data,accounts}', '[]'::jsonb)) acct
    cross join lateral jsonb_array_elements(coalesce(acct->'payouts', '[]'::jsonb)) payout
    where payout->>'note' = 'public payout note'
  ) then
    raise exception 'account_insights_verify: payout note must appear under payouts[]';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(v_payload #> '{data,accounts}', '[]'::jsonb)) acct
    cross join lateral jsonb_array_elements(coalesce(acct->'payouts', '[]'::jsonb)) payout
    where payout ?| array['account_id', 'user_id', 'created_at', 'updated_at']
  ) then
    raise exception 'account_insights_verify: forbidden payout-level fields in RPC payload';
  end if;

  -- Private-profile denial for anon viewer
  select id into v_private_profile
  from public.profiles
  where coalesce(is_private, false) = true
  limit 1;

  if v_private_profile is not null then
    v_payload := public.rpc_v1_profile_account_insights(v_private_profile::text);
    if coalesce(v_payload #>> '{meta,can_view}', 'true') = 'true'
       and jsonb_array_length(coalesce(v_payload #> '{data,accounts}', '[]'::jsonb)) > 0 then
      raise exception 'account_insights_verify: private profile leaked accounts to anon viewer';
    end if;
  else
    raise notice 'account_insights_verify: private-profile denial skipped — no private profile';
  end if;

  -- Blocked-user denial requires JWT context; document-only unless caller sets request.jwt.claim.sub
  if v_other is not null then
    raise notice 'account_insights_verify: blocked-user denial requires authenticated JWT — set request.jwt.claim.sub manually to test';
  end if;

  -- Non-owner direct payout mutation should fail under RLS when executed as another role
  raise notice 'account_insights_verify: non-owner RLS denial — run SET ROLE authenticated + JWT as non-owner separately';

  delete from public.account_payout_entries where id = v_test_payout_id;
  delete from public.accounts where id = v_test_account_id;

  raise notice 'account_insights_verify: passed';
end;
$$;

rollback;
5