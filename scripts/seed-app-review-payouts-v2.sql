-- =============================================================================
-- TradeTraxs App Review — payout history seed V2 (MANUAL RUN ONLY)
-- Namespace: app_review_seed:v2:payouts
--
-- >>> REVIEW ACCOUNT <<<
-- TARGET_USER_ID:        d3aeace4-e2a5-4679-b47d-23d40d6e2c59
-- EXPECTED_REVIEW_EMAIL: iosreview@tradetraxs.com
--
-- Requires v2 accounts from seed-app-review-trading-history-v2.sql:
--   Eval:  92a0fabd-25dd-415a-868d-657ddfb4c5d9 (Evaluation Account)
--   Live:  42e6834f-52e6-4a78-802d-2f30808dc588 (Apple Review Futures)
--
-- Inserts manual payout log rows + payout achievements (no funded-cycle RPC).
-- =============================================================================

BEGIN;

CREATE TEMP TABLE _app_review_v2_payout_entries (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  amount numeric(14, 2) NOT NULL,
  payout_date date NOT NULL,
  note text
) ON COMMIT DROP;

CREATE TEMP TABLE _app_review_v2_payout_achievements (
  id uuid PRIMARY KEY,
  achievement_type text NOT NULL,
  category text NOT NULL,
  title text NOT NULL,
  description text,
  achieved_at timestamptz NOT NULL,
  value_numeric numeric,
  value_text text,
  account_id uuid,
  is_public boolean NOT NULL DEFAULT false,
  is_featured boolean NOT NULL DEFAULT false,
  sort_order int NOT NULL DEFAULT 0,
  metadata jsonb NOT NULL
) ON COMMIT DROP;

INSERT INTO _app_review_v2_payout_entries VALUES
-- Evaluation Account (prop-style manual log)
('40882a96-87a2-460c-85aa-1386062f421e'::uuid, '92a0fabd-25dd-415a-868d-657ddfb4c5d9'::uuid, 850.00, '2026-03-14'::date, '[app_review_seed:v2:payouts] First eval withdrawal to personal bank.'),
('0dc1bd4b-3646-4e5e-822e-e74a2846c9ee'::uuid, '92a0fabd-25dd-415a-868d-657ddfb4c5d9'::uuid, 1200.00, '2026-05-24'::date, '[app_review_seed:v2:payouts] Payout after passing eval — consistency rule met.'),
('a58e9676-fad8-4ea1-845d-e641b3e68dc7'::uuid, '92a0fabd-25dd-415a-868d-657ddfb4c5d9'::uuid, 1500.00, '2026-08-15'::date, '[app_review_seed:v2:payouts] Summer performance payout.'),
-- Personal live account (smaller live payout)
('5ae7ad06-ec78-486c-84c1-5525d87f2d2c'::uuid, '42e6834f-52e6-4a78-802d-2f30808dc588'::uuid, 420.00, '2026-07-02'::date, '[app_review_seed:v2:payouts] Live MNQ profits — partial withdraw.');

INSERT INTO _app_review_v2_payout_achievements VALUES
('d7b71030-5e6f-4977-8323-9069b17a51e5'::uuid, 'prop_firm_payout', 'prop_firm_payouts',
 'Prop Firm Payout', 'Recorded $1,500 evaluation payout after meeting firm rules.',
 '2026-08-15T16:00:00-04:00'::timestamptz, 1500, null, '92a0fabd-25dd-415a-868d-657ddfb4c5d9'::uuid,
 true, true, 10, '{"seed":"app_review_seed:v2:payouts","key":"prop_firm_payout_1500"}'::jsonb),
('85b85fa2-666f-4967-8ff3-020229b74161'::uuid, 'live_trading_payout', 'live_trading_payouts',
 'Live Trading Payout', 'Withdrew live account profits to bank.',
 '2026-07-02T12:00:00-04:00'::timestamptz, 420, null, '42e6834f-52e6-4a78-802d-2f30808dc588'::uuid,
 false, false, 11, '{"seed":"app_review_seed:v2:payouts","key":"live_payout_420"}'::jsonb);

DO $$
DECLARE
  target_user_id uuid := 'd3aeace4-e2a5-4679-b47d-23d40d6e2c59'::uuid;
  expected_review_email text := 'iosreview@tradetraxs.com';
  auth_email text;
  v_eval_id uuid := '92a0fabd-25dd-415a-868d-657ddfb4c5d9'::uuid;
  v_live_id uuid := '42e6834f-52e6-4a78-802d-2f30808dc588'::uuid;
  inserted_entries int := 0;
  inserted_ach int := 0;
BEGIN
  SELECT u.email INTO auth_email FROM auth.users u WHERE u.id = target_user_id;
  IF auth_email IS NULL THEN
    RAISE EXCEPTION 'auth.users has no row for %', target_user_id;
  END IF;
  IF lower(trim(auth_email)) <> lower(trim(expected_review_email)) THEN
    RAISE EXCEPTION 'Email mismatch for review account.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = v_eval_id AND a.user_id = target_user_id) THEN
    RAISE EXCEPTION 'Evaluation Account % missing for review user — run trading history v2 seed first.', v_eval_id;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = v_live_id AND a.user_id = target_user_id) THEN
    RAISE EXCEPTION 'Live account % missing for review user — run trading history v2 seed first.', v_live_id;
  END IF;

  INSERT INTO public.account_payout_entries (id, account_id, user_id, amount, payout_date, note)
  SELECT e.id, e.account_id, target_user_id, e.amount, e.payout_date, e.note
  FROM _app_review_v2_payout_entries e
  WHERE NOT EXISTS (
    SELECT 1 FROM public.account_payout_entries x WHERE x.id = e.id
  );

  GET DIAGNOSTICS inserted_entries = ROW_COUNT;

  INSERT INTO public.achievements (
    id, user_id, achievement_type, category, title, description, achieved_at,
    value_numeric, value_text, account_id, is_public, is_featured, sort_order, metadata
  )
  SELECT
    a.id, target_user_id, a.achievement_type, a.category, a.title, a.description, a.achieved_at,
    a.value_numeric, a.value_text, a.account_id, a.is_public, a.is_featured, a.sort_order, a.metadata
  FROM _app_review_v2_payout_achievements a
  WHERE NOT EXISTS (
    SELECT 1 FROM public.achievements x WHERE x.id = a.id AND x.user_id = target_user_id
  );

  GET DIAGNOSTICS inserted_ach = ROW_COUNT;

  RAISE NOTICE 'App Review payouts v2: entries inserted=%, achievements inserted=%',
    inserted_entries, inserted_ach;
END $$;

COMMIT;

-- =============================================================================
-- OPTIONAL ROLLBACK (separate transaction)
-- =============================================================================
-- BEGIN;
-- DELETE FROM public.account_payout_entries
--  WHERE user_id = 'd3aeace4-e2a5-4679-b47d-23d40d6e2c59'::uuid
--    AND note LIKE '[app_review_seed:v2:payouts]%';
-- DELETE FROM public.achievements
--  WHERE user_id = 'd3aeace4-e2a5-4679-b47d-23d40d6e2c59'::uuid
--    AND metadata->>'seed' = 'app_review_seed:v2:payouts';
-- COMMIT;
