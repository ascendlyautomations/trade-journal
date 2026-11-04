-- =============================================================================
-- TradeTraxs Guest Showcase demo seed — PAYOUTS (GENERATED)
-- Namespace: showcase_demo:v1
-- Target: 3daf15b8-2f5d-48c8-ac98-75bca6c878f4 (tradetraxsdemo@gmail.com)
-- Run AFTER seed-showcase-demo-v1-trades.sql
-- Funded: 3 completed account_payout_cycles (not ledger entries)
-- Live: 2 account_payout_entries + matching live_trading_payout achievements
-- =============================================================================

BEGIN;

CREATE TEMP TABLE _showcase_demo_v1_cycles (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  payout_amount numeric NOT NULL,
  payout_date date NOT NULL,
  balance_before numeric NOT NULL,
  balance_after numeric NOT NULL,
  cycle_number int NOT NULL,
  note text NOT NULL
) ON COMMIT DROP;

CREATE TEMP TABLE _showcase_demo_v1_ledger (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  amount numeric NOT NULL,
  payout_date date NOT NULL,
  note text NOT NULL
) ON COMMIT DROP;

CREATE TEMP TABLE _showcase_demo_v1_payout_ach (
  id uuid PRIMARY KEY,
  achievement_type text NOT NULL,
  category text NOT NULL,
  title text NOT NULL,
  description text,
  achieved_at timestamptz NOT NULL,
  value_numeric numeric,
  account_id uuid,
  is_public boolean NOT NULL,
  is_featured boolean NOT NULL,
  sort_order int NOT NULL,
  metadata jsonb NOT NULL
) ON COMMIT DROP;

INSERT INTO _showcase_demo_v1_cycles VALUES
('0d23a8ef-7403-46c0-8672-35653e7de96a'::uuid, 'b1faf4c1-181f-4b1d-8881-f19ccbdf61fc'::uuid, 950, '2026-08-08'::date, 51200.89, 50250.89, 1, '[showcase_demo:v1:payouts] Funded payout cycle 1.'),
('ecae3cf0-c86d-42bf-8102-7e7889bb8c52'::uuid, 'b1faf4c1-181f-4b1d-8881-f19ccbdf61fc'::uuid, 1200, '2026-09-12'::date, 52127.28, 50927.28, 2, '[showcase_demo:v1:payouts] Funded payout cycle 2.'),
('4aa1c481-b4ec-4df8-8427-9ef2b3c6be29'::uuid, 'b1faf4c1-181f-4b1d-8881-f19ccbdf61fc'::uuid, 1350, '2026-10-17'::date, 53019.37, 51669.37, 3, '[showcase_demo:v1:payouts] Funded payout cycle 3.');

INSERT INTO _showcase_demo_v1_ledger VALUES
('1460a83a-0742-4a32-8a10-ad9ec12f20d6'::uuid, 'ac7591b3-81b1-4b36-8336-3b2fd4694d01'::uuid, 480, '2026-08-22'::date, '[showcase_demo:v1:payouts] Live MNQ profits — partial withdraw.'),
('5b045131-2724-4fdb-87d7-393bfc31c7f3'::uuid, 'ac7591b3-81b1-4b36-8336-3b2fd4694d01'::uuid, 620, '2026-10-03'::date, '[showcase_demo:v1:payouts] Live account withdrawal after green month.');

INSERT INTO _showcase_demo_v1_payout_ach VALUES
('30eec879-902c-4554-8bfe-5e9c46412a54'::uuid, 'prop_firm_payout', 'prop_firm_payouts', 'Prop Firm Payout', 'Funded account payout after meeting firm rules.', '2026-08-08T16:00:00-04:00'::timestamptz, 950, 'b1faf4c1-181f-4b1d-8881-f19ccbdf61fc'::uuid, true, true, 10, '{"seed":"showcase_demo:v1","key":"prop_payout_950","cycle_id":"0d23a8ef-7403-46c0-8672-35653e7de96a"}'::jsonb),
('745cb1b4-a1c6-4ce6-86fd-7528c477df82'::uuid, 'prop_firm_payout', 'prop_firm_payouts', 'Prop Firm Payout', 'Second funded payout — consistency rule met.', '2026-09-12T16:00:00-04:00'::timestamptz, 1200, 'b1faf4c1-181f-4b1d-8881-f19ccbdf61fc'::uuid, true, false, 11, '{"seed":"showcase_demo:v1","key":"prop_payout_1200","cycle_id":"ecae3cf0-c86d-42bf-8102-7e7889bb8c52"}'::jsonb),
('4eecc58c-bfb2-4ac7-8e7b-321761481771'::uuid, 'prop_firm_payout', 'prop_firm_payouts', 'Prop Firm Payout', 'Third funded payout of the showcase period.', '2026-10-17T16:00:00-04:00'::timestamptz, 1350, 'b1faf4c1-181f-4b1d-8881-f19ccbdf61fc'::uuid, true, false, 12, '{"seed":"showcase_demo:v1","key":"prop_payout_1350","cycle_id":"4aa1c481-b4ec-4df8-8427-9ef2b3c6be29"}'::jsonb),
('ab68feeb-bfd8-48de-8855-c84a219a8195'::uuid, 'live_trading_payout', 'live_trading_payouts', 'Live Trading Payout', 'Withdrew live account profits to bank.', '2026-08-22T12:00:00-04:00'::timestamptz, 480, 'ac7591b3-81b1-4b36-8336-3b2fd4694d01'::uuid, false, false, 13, '{"seed":"showcase_demo:v1","key":"live_payout_480","ledger_id":"1460a83a-0742-4a32-8a10-ad9ec12f20d6"}'::jsonb),
('46b0129e-7df0-4faf-81de-96e7603c7f5d'::uuid, 'live_trading_payout', 'live_trading_payouts', 'Live Trading Payout', 'Second live withdrawal of the showcase period.', '2026-10-03T12:00:00-04:00'::timestamptz, 620, 'ac7591b3-81b1-4b36-8336-3b2fd4694d01'::uuid, false, false, 14, '{"seed":"showcase_demo:v1","key":"live_payout_620","ledger_id":"5b045131-2724-4fdb-87d7-393bfc31c7f3"}'::jsonb);

DO $$
DECLARE
  target_user_id uuid := '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid;
  expected_email text := 'tradetraxsdemo@gmail.com';
  auth_email text;
  v_funded uuid := 'b1faf4c1-181f-4b1d-8881-f19ccbdf61fc'::uuid;
  v_live uuid := 'ac7591b3-81b1-4b36-8336-3b2fd4694d01'::uuid;
BEGIN
  SELECT u.email INTO auth_email FROM auth.users u WHERE u.id = target_user_id;
  IF lower(trim(auth_email)) <> lower(trim(expected_email)) THEN
    RAISE EXCEPTION 'Email mismatch for showcase payouts seed.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = v_funded AND a.user_id = target_user_id) THEN
    RAISE EXCEPTION 'Funded showcase account missing — run trades seed first.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = v_live AND a.user_id = target_user_id) THEN
    RAISE EXCEPTION 'Live showcase account missing — run trades seed first.';
  END IF;

  INSERT INTO public.account_payout_cycles (
    id, user_id, account_id, started_at, ended_at, cycle_start_balance,
    payout_amount, balance_before_payout, balance_after_payout,
    drawdown_behavior, cycle_number, note
  )
  SELECT
    c.id, target_user_id, c.account_id,
    (c.payout_date::text || 'T09:00:00-04:00')::timestamptz,
    (c.payout_date::text || 'T16:30:00-04:00')::timestamptz,
    c.balance_before,
    c.payout_amount, c.balance_before, c.balance_after,
    'balance_based', c.cycle_number, c.note
  FROM _showcase_demo_v1_cycles c
  WHERE NOT EXISTS (SELECT 1 FROM public.account_payout_cycles x WHERE x.id = c.id);

  INSERT INTO public.account_payout_entries (id, account_id, user_id, amount, payout_date, note)
  SELECT e.id, e.account_id, target_user_id, e.amount, e.payout_date, e.note
  FROM _showcase_demo_v1_ledger e
  WHERE NOT EXISTS (SELECT 1 FROM public.account_payout_entries x WHERE x.id = e.id);

  INSERT INTO public.achievements (
    id, user_id, achievement_type, category, title, description, achieved_at,
    value_numeric, value_text, account_id, is_public, is_featured, sort_order, metadata
  )
  SELECT
    a.id, target_user_id, a.achievement_type, a.category, a.title, a.description, a.achieved_at,
    a.value_numeric, null, a.account_id, a.is_public, a.is_featured, a.sort_order, a.metadata
  FROM _showcase_demo_v1_payout_ach a
  WHERE NOT EXISTS (SELECT 1 FROM public.achievements x WHERE x.id = a.id);

END $$;

COMMIT;
