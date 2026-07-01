-- affiliate_payout_balance: total earnings from commission ledger
-- (profiles.referral_earnings, else sum of referrals.amount_earned).
-- Payout reserves unchanged: since last = total − approved − paid; available = since − pending.
--
-- Production signature: RETURNS jsonb (matches live database).
-- Earlier repo migrations declared json; live DB uses jsonb — this migration aligns with production
-- so CREATE OR REPLACE succeeds without DROP.

create or replace function public.affiliate_payout_balance(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_recorded numeric(14, 2);
  v_ledger_sum numeric(14, 2);
  v_ref_count bigint;
  v_total numeric(14, 2);
  v_paid_sum numeric(14, 2);
  v_pending_sum numeric(14, 2);
  v_approved_sum numeric(14, 2);
  v_consumed numeric(14, 2);
  v_since numeric(14, 2);
  v_available numeric(14, 2);
  v_last_paid timestamptz;
  v_minimum numeric(14, 2) := 100;
  v_can_request boolean;
begin
  if auth.uid() is distinct from p_user_id then
    raise exception 'Forbidden' using errcode = '42501';
  end if;

  select
    coalesce(p.referral_earnings, 0)::numeric(14, 2),
    coalesce(p.referral_count, 0)::bigint
  into v_recorded, v_ref_count
  from public.profiles p
  where p.id = p_user_id;

  if not found then
    return jsonb_build_object(
      'referralCount', 0,
      'totalEarnings', 0,
      'totalPaid', 0,
      'earningsSinceLastPayout', 0,
      'pendingReserved', 0,
      'approvedReserved', 0,
      'availableToRequest', 0,
      'lastPaidAt', null,
      'minimumPayout', v_minimum,
      'canRequest', false
    );
  end if;

  if v_recorded > 0 then
    v_total := round(v_recorded, 2);
  else
    select coalesce(sum(r.amount_earned), 0)::numeric(14, 2)
    into v_ledger_sum
    from public.referrals r
    where r.referrer_user_id = p_user_id;

    v_total := round(v_ledger_sum, 2);
  end if;

  select coalesce(sum(pr.amount), 0)::numeric(14, 2)
  into v_paid_sum
  from public.affiliate_payout_requests pr
  where pr.user_id = p_user_id
    and pr.status = 'paid';

  select coalesce(sum(pr.amount), 0)::numeric(14, 2)
  into v_pending_sum
  from public.affiliate_payout_requests pr
  where pr.user_id = p_user_id
    and pr.status = 'pending';

  select coalesce(sum(pr.amount), 0)::numeric(14, 2)
  into v_approved_sum
  from public.affiliate_payout_requests pr
  where pr.user_id = p_user_id
    and pr.status = 'approved';

  v_consumed := round((v_approved_sum + v_paid_sum)::numeric, 2);

  v_since := round((v_total - v_consumed)::numeric, 2);
  if v_since < 0 then
    v_since := 0;
  end if;

  v_available := round((v_since - v_pending_sum)::numeric, 2);
  if v_available < 0 then
    v_available := 0;
  end if;

  select max(pr.paid_at)
  into v_last_paid
  from public.affiliate_payout_requests pr
  where pr.user_id = p_user_id
    and pr.status = 'paid';

  v_can_request := v_available >= v_minimum;

  return jsonb_build_object(
    'referralCount', v_ref_count,
    'totalEarnings', v_total,
    'totalPaid', v_paid_sum,
    'earningsSinceLastPayout', v_since,
    'pendingReserved', v_pending_sum,
    'approvedReserved', v_approved_sum,
    'availableToRequest', v_available,
    'lastPaidAt', v_last_paid,
    'minimumPayout', v_minimum,
    'canRequest', v_can_request
  );
end;
$$;

comment on function public.affiliate_payout_balance(uuid) is
  'Affiliate payout math: total = profiles.referral_earnings (else sum referrals.amount_earned); since last = total − approved − paid; available = since − pending; $100 min (canRequest). Caller must be p_user_id.';

revoke all on function public.affiliate_payout_balance(uuid) from public;
grant execute on function public.affiliate_payout_balance(uuid) to authenticated;
