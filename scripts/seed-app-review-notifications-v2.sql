-- =============================================================================
-- TradeTraxs App Review — Activity notifications seed V2 (MANUAL RUN ONLY)
-- Namespace: app_review_seed:v2:notifications
--
-- >>> REVIEW ACCOUNT <<<
-- TARGET_USER_ID:        d3aeace4-e2a5-4679-b47d-23d40d6e2c59
-- EXPECTED_REVIEW_EMAIL: iosreview@tradetraxs.com
--
-- Run AFTER seed-app-review-trading-history-v2.sql (optional: links likes/comments
-- to public v2 trades). Supabase SQL editor / service role. Choose "Run without RLS"
-- if prompted (temp staging tables only).
-- =============================================================================

BEGIN;

CREATE TEMP TABLE _app_review_v2_notifications (
  id uuid PRIMARY KEY,
  type text NOT NULL,
  created_at timestamptz NOT NULL,
  content text,
  read boolean NOT NULL DEFAULT false,
  trade_id uuid,
  profile_post_id uuid,
  sender_required boolean NOT NULL DEFAULT false
) ON COMMIT DROP;

INSERT INTO _app_review_v2_notifications (id, type, created_at, content, read, trade_id, profile_post_id, sender_required) VALUES
-- Trading reports (no sender; system-style Activity rows)
('87c84767-8773-4350-89f3-09ee078fcad3'::uuid, 'trading_report', '2025-10-06T09:00:00-04:00'::timestamptz, '{"seed":"app_review_seed:v2:notifications","title":"Weekly trading report","body":"Your weekly trading summary is ready to review.","href":"/dashboard?report=2025-W40","periodKey":"2025-W40","periodId":"2025-W40","kind":"weekly"}', true, null, null, false),
('207e5598-2f8f-4868-8a82-8b0560c5b196'::uuid, 'trading_report', '2025-10-31T09:00:00-04:00'::timestamptz, '{"seed":"app_review_seed:v2:notifications","title":"October trading report","body":"Your October summary is ready to review.","href":"/dashboard?report=2025-10","periodKey":"2025-10","periodId":"2025-10","kind":"monthly"}', true, null, null, false),
('545dc112-2883-43a4-8c0d-11c38c8a4803'::uuid, 'trading_report', '2025-11-10T09:00:00-04:00'::timestamptz, '{"seed":"app_review_seed:v2:notifications","title":"Weekly trading report","body":"Your weekly trading summary is ready to review.","href":"/dashboard?report=2025-W45","periodKey":"2025-W45","periodId":"2025-W45","kind":"weekly"}', true, null, null, false),
('b9b01b09-76dc-4b77-8609-6bc006437584'::uuid, 'trading_report', '2025-12-01T09:00:00-04:00'::timestamptz, '{"seed":"app_review_seed:v2:notifications","title":"November trading report","body":"Your November summary is ready to review.","href":"/dashboard?report=2025-11","periodKey":"2025-11","periodId":"2025-11","kind":"monthly"}', true, null, null, false),
('d2832fec-bb1e-48c8-81bc-4a0a25ebc88f'::uuid, 'trading_report', '2026-01-13T09:00:00-04:00'::timestamptz, '{"seed":"app_review_seed:v2:notifications","title":"Weekly trading report","body":"Your weekly trading summary is ready to review.","href":"/dashboard?report=2026-W02","periodKey":"2026-W02","periodId":"2026-W02","kind":"weekly"}', true, null, null, false),
('550404b1-16eb-4e4d-8bd4-245e93782523'::uuid, 'trading_report', '2026-02-02T09:00:00-04:00'::timestamptz, '{"seed":"app_review_seed:v2:notifications","title":"January trading report","body":"Your January summary is ready to review.","href":"/dashboard?report=2026-01","periodKey":"2026-01","periodId":"2026-01","kind":"monthly"}', true, null, null, false),
('912964a7-81e3-466a-87d7-2e7952b4ff46'::uuid, 'trading_report', '2026-04-07T09:00:00-04:00'::timestamptz, '{"seed":"app_review_seed:v2:notifications","title":"Weekly trading report","body":"Your weekly trading summary is ready to review.","href":"/dashboard?report=2026-W14","periodKey":"2026-W14","periodId":"2026-W14","kind":"weekly"}', true, null, null, false),
('d2f236ca-364b-4f90-8651-3ec801c81618'::uuid, 'trading_report', '2026-05-01T09:00:00-04:00'::timestamptz, '{"seed":"app_review_seed:v2:notifications","title":"April trading report","body":"Your April summary is ready to review.","href":"/dashboard?report=2026-04","periodKey":"2026-04","periodId":"2026-04","kind":"monthly"}', true, null, null, false),
('db56b260-fc0e-4070-8593-4ae519bca63e'::uuid, 'trading_report', '2026-07-14T09:00:00-04:00'::timestamptz, '{"seed":"app_review_seed:v2:notifications","title":"Weekly trading report","body":"Your weekly trading summary is ready to review.","href":"/dashboard?report=2026-W28","periodKey":"2026-W28","periodId":"2026-W28","kind":"weekly"}', true, null, null, false),
('3dd4e964-eab0-49a8-883f-570683ca53b1'::uuid, 'trading_report', '2026-08-03T09:00:00-04:00'::timestamptz, '{"seed":"app_review_seed:v2:notifications","title":"July trading report","body":"Your July summary is ready to review.","href":"/dashboard?report=2026-07","periodKey":"2026-07","periodId":"2026-07","kind":"monthly"}', true, null, null, false),
('7686e5c8-4563-4409-8533-4756ca2fda86'::uuid, 'trading_report', '2026-09-08T09:00:00-04:00'::timestamptz, '{"seed":"app_review_seed:v2:notifications","title":"Weekly trading report","body":"Your weekly trading summary is ready to review.","href":"/dashboard?report=2026-W36","periodKey":"2026-W36","periodId":"2026-W36","kind":"weekly"}', false, null, null, false),
-- Affiliate-style (no sender FK)
('a4c8e2d1-9b3f-4e2a-8c1d-6f7e8d9a0b1c'::uuid, 'affiliate_commission_earned', '2026-06-12T11:00:00-04:00'::timestamptz, '{"seed":"app_review_seed:v2:notifications","title":"Commission earned","body":"A referred user became a paying TraxPro subscriber. You earned $24.00.","href":"/affiliate/dashboard"}', true, null, null, false),
-- Engagement (requires another real profile as sender; skipped if none exists)
('e951a9b3-7340-4674-8c05-c9fe4215e2f3'::uuid, 'like', '2026-08-15T14:30:00-04:00'::timestamptz, '{"seed":"app_review_seed:v2:notifications"}', false, null, null, true),
('1d9978e5-63d4-4ffb-8151-ea39fea0aa86'::uuid, 'like', '2026-08-16T14:30:00-04:00'::timestamptz, '{"seed":"app_review_seed:v2:notifications"}', false, null, null, true),
('8b7281f9-8a71-414f-8590-52f279538a71'::uuid, 'comment', '2026-08-17T14:30:00-04:00'::timestamptz, 'Nice breakdown on this session — respect the risk control.', false, null, null, true),
('c30e0772-248e-4861-8b4f-80a9631b853d'::uuid, 'follow_request_accepted', '2026-08-18T14:30:00-04:00'::timestamptz, '{"seed":"app_review_seed:v2:notifications"}', false, null, null, true);

DO $$
DECLARE
  target_user_id uuid := 'd3aeace4-e2a5-4679-b47d-23d40d6e2c59'::uuid;
  expected_review_email text := 'iosreview@tradetraxs.com';
  auth_email text;
  profile_ok boolean;
  demo_sender_id uuid;
  trade_ids uuid[] := '{}'::uuid[];
  post_ids uuid[] := '{}'::uuid[];
  inserted int := 0;
  skipped_engagement int := 0;
  r record;
  v_trade_id uuid;
  v_post_id uuid;
BEGIN
  IF target_user_id IS NULL OR target_user_id = '00000000-0000-0000-0000-000000000000'::uuid THEN
    RAISE EXCEPTION 'Invalid target_user_id.';
  END IF;
  IF expected_review_email IS NULL OR trim(expected_review_email) = '' THEN
    RAISE EXCEPTION 'Invalid expected_review_email.';
  END IF;

  SELECT u.email INTO auth_email FROM auth.users u WHERE u.id = target_user_id;
  IF auth_email IS NULL THEN
    RAISE EXCEPTION 'auth.users has no row for %', target_user_id;
  END IF;
  IF lower(trim(auth_email)) <> lower(trim(expected_review_email)) THEN
    RAISE EXCEPTION 'Email mismatch for review account.';
  END IF;

  SELECT EXISTS(SELECT 1 FROM public.profiles p WHERE p.id = target_user_id) INTO profile_ok;
  IF NOT profile_ok THEN
    RAISE EXCEPTION 'profiles.id missing for %', target_user_id;
  END IF;

  SELECT p.id INTO demo_sender_id
  FROM public.profiles p
  WHERE p.id <> target_user_id
    AND coalesce(p.is_banned, false) = false
  ORDER BY p.created_at NULLS LAST
  LIMIT 1;

  SELECT coalesce(array_agg(t.id ORDER BY t.trade_date, t.import_fingerprint), '{}'::uuid[])
  INTO trade_ids
  FROM (
    SELECT t.id, t.trade_date, t.import_fingerprint
    FROM public.trades t
    WHERE t.user_id = target_user_id
      AND t.is_public = true
      AND t.import_fingerprint LIKE 'app_review_seed:v2:%'
    ORDER BY t.trade_date DESC
    LIMIT 3
  ) t;

  SELECT coalesce(array_agg(p.id ORDER BY p.created_at), '{}'::uuid[])
  INTO post_ids
  FROM (
    SELECT p.id, p.created_at
    FROM public.profile_posts p
    WHERE p.user_id = target_user_id
      AND p.content LIKE '[app_review_seed:v2]%'
    ORDER BY p.created_at DESC
    LIMIT 1
  ) p;

  FOR r IN SELECT * FROM _app_review_v2_notifications ORDER BY created_at LOOP
    IF r.sender_required AND demo_sender_id IS NULL THEN
      skipped_engagement := skipped_engagement + 1;
      CONTINUE;
    END IF;

    IF r.type IN ('like', 'comment') AND array_length(trade_ids, 1) IS NULL THEN
      skipped_engagement := skipped_engagement + 1;
      CONTINUE;
    END IF;

    v_trade_id := r.trade_id;
    v_post_id := r.profile_post_id;

    IF r.type = 'like' AND v_trade_id IS NULL AND array_length(trade_ids, 1) >= 1 THEN
      IF r.id = 'e951a9b3-7340-4674-8c05-c9fe4215e2f3'::uuid THEN
        v_trade_id := trade_ids[1];
      ELSIF r.id = '1d9978e5-63d4-4ffb-8151-ea39fea0aa86'::uuid AND array_length(trade_ids, 1) >= 2 THEN
        v_trade_id := trade_ids[2];
      ELSE
        v_trade_id := trade_ids[1];
      END IF;
    END IF;

    IF r.type = 'comment' AND v_trade_id IS NULL AND array_length(trade_ids, 1) >= 1 THEN
      v_trade_id := trade_ids[least(3, array_length(trade_ids, 1))];
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.id = r.id AND n.user_id = target_user_id
    ) THEN
      CONTINUE;
    END IF;

    INSERT INTO public.notifications (
      id, user_id, sender_id, type, content, read, created_at, trade_id, profile_post_id
    ) VALUES (
      r.id,
      target_user_id,
      CASE WHEN r.sender_required THEN demo_sender_id ELSE NULL END,
      r.type,
      r.content,
      r.read,
      r.created_at,
      v_trade_id,
      v_post_id
    );

    inserted := inserted + 1;
  END LOOP;

  RAISE NOTICE 'App Review notifications v2: inserted=%, skipped_engagement (no sender/trades)=%',
    inserted, skipped_engagement;
END $$;

COMMIT;

-- =============================================================================
-- OPTIONAL ROLLBACK (separate transaction)
-- =============================================================================
-- BEGIN;
-- DELETE FROM public.notifications
--  WHERE user_id = 'd3aeace4-e2a5-4679-b47d-23d40d6e2c59'::uuid
--    AND (
--      id IN (
--        '87c84767-8773-4350-89f3-09ee078fcad3'::uuid,
--        '207e5598-2f8f-4868-8a82-8b0560c5b196'::uuid,
--        '545dc112-2883-43a4-8c0d-11c38c8a4803'::uuid,
--        'b9b01b09-76dc-4b77-8609-6bc006437584'::uuid,
--        'd2832fec-bb1e-48c8-81bc-4a0a25ebc88f'::uuid,
--        '550404b1-16eb-4e4d-8bd4-245e93782523'::uuid,
--        '912964a7-81e3-466a-87d7-2e7952b4ff46'::uuid,
--        'd2f236ca-364b-4f90-8651-3ec801c81618'::uuid,
--        'db56b260-fc0e-4070-8593-4ae519bca63e'::uuid,
--        '3dd4e964-eab0-49a8-883f-570683ca53b1'::uuid,
--        '7686e5c8-4563-4409-8533-4756ca2fda86'::uuid,
--        'a4c8e2d1-9b3f-4e2a-8c1d-6f7e8d9a0b1c'::uuid,
--        'e951a9b3-7340-4674-8c05-c9fe4215e2f3'::uuid,
--        '1d9978e5-63d4-4ffb-8151-ea39fea0aa86'::uuid,
--        '8b7281f9-8a71-414f-8590-52f279538a71'::uuid,
--        'c30e0772-248e-4861-8b4f-80a9631b853d'::uuid
--      )
--      OR content LIKE '%app_review_seed:v2:notifications%'
--    );
-- COMMIT;
