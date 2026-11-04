-- =============================================================================
-- Showcase demo v1 — VALIDATION & ROLLBACK QUERIES (read-only section)
-- Target: 3daf15b8-2f5d-48c8-ac98-75bca6c878f4 (tradetraxsdemo@gmail.com)
-- Namespace: showcase_demo:v1
-- Generator pre-apply stats: {
  "tradeCount": 300,
  "checkInCount": 93,
  "winRate": 0.6120401337792643,
  "totalPnl": 5211.18,
  "maxDrawdown": 1482.58,
  "psychCoverage": 0.8466666666666667,
  "rrPairedCoverage": 1,
  "publicTrades": 11,
  "feedPosts": 11,
  "firstDate": "2026-05-01",
  "lastDate": "2026-10-30"
}
-- Payout plan funded PnL=3431.1 live PnL=1308.48
-- Deterministic accounts:
--   eval:   9eeb99e3-a3b9-4a8c-855e-305f2dcbd880
--   funded: b1faf4c1-181f-4b1d-8881-f19ccbdf61fc
--   live:   ac7591b3-81b1-4b36-8336-3b2fd4694d01
--   sim:    bc077977-512b-452c-88ec-0be7ee4b6c85
-- =============================================================================

-- 1) Identity guard (must return 1 row, email tradetraxsdemo@gmail.com)
SELECT id, email FROM auth.users WHERE id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid;

-- 2) Trade counts & date window (demo rows only)
SELECT
  count(*) AS demo_trades,
  min(trade_date) AS min_date,
  max(trade_date) AS max_date,
  round(sum(pnl)::numeric, 2) AS demo_pnl
FROM public.trades
WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid
  AND import_fingerprint LIKE 'showcase_demo:v1:%';

-- 3) Non-demo trades preserved (compare before/after apply)
SELECT count(*) AS non_demo_trades
FROM public.trades
WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid
  AND (import_fingerprint IS NULL OR import_fingerprint NOT LIKE 'showcase_demo:v1:%');

-- 4) R:R coverage
SELECT
  count(*) FILTER (WHERE rr IS NOT NULL AND max_rr_reached IS NOT NULL) AS rr_paired,
  count(*) FILTER (WHERE realized_rr IS NOT NULL) AS with_realized_rr,
  count(*) AS total_demo
FROM public.trades
WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid
  AND import_fingerprint LIKE 'showcase_demo:v1:%';

-- 5) Psychology coverage
SELECT
  round(100.0 * count(*) FILTER (
    WHERE emotion IS NOT NULL AND confidence IS NOT NULL AND execution_rating IS NOT NULL
  ) / nullif(count(*), 0), 1) AS psych_pct
FROM public.trades
WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid
  AND import_fingerprint LIKE 'showcase_demo:v1:%';

-- 6) Strategy distribution
SELECT strategy, count(*) AS n, round(sum(pnl)::numeric, 2) AS pnl
FROM public.trades
WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid
  AND import_fingerprint LIKE 'showcase_demo:v1:%'
GROUP BY strategy
ORDER BY n DESC;

-- 7) Account mix
SELECT account_id, mode, count(*) AS n, round(sum(pnl)::numeric, 2) AS pnl
FROM public.trades
WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid
  AND import_fingerprint LIKE 'showcase_demo:v1:%'
GROUP BY account_id, mode;

-- 8) Payouts (no double-count: funded = cycles, live = ledger)
SELECT 'cycles' AS kind, count(*), round(sum(payout_amount)::numeric, 2) AS total
FROM public.account_payout_cycles
WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid AND note LIKE '[showcase_demo:v1:payouts]%'
UNION ALL
SELECT 'live_ledger', count(*), round(sum(amount)::numeric, 2)
FROM public.account_payout_entries
WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid AND note LIKE '[showcase_demo:v1:payouts]%';

-- 9) Achievements tagged with seed
SELECT achievement_type, count(*), round(sum(coalesce(value_numeric, 0))::numeric, 2)
FROM public.achievements
WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid AND metadata->>'seed' = 'showcase_demo:v1'
GROUP BY achievement_type;

-- 10) Public feed posts linked to demo trades
SELECT count(*) FROM public.posts p
JOIN public.trades t ON t.id = p.trade_id
WHERE p.user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid AND t.import_fingerprint LIKE 'showcase_demo:v1:%';

-- 11) Daily check-ins (demo-tagged notes)
SELECT count(*) AS demo_checkins
FROM public.trader_daily_check_ins
WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid AND notes LIKE '[showcase_demo:v1]%';

-- 12) Duplicate fingerprint guard (expect 0 rows)
SELECT import_fingerprint, count(*)
FROM public.trades
WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid AND import_fingerprint LIKE 'showcase_demo:v1:%'
GROUP BY import_fingerprint
HAVING count(*) > 1;

-- =============================================================================
-- OPTIONAL ROLLBACK — separate transaction; removes ONLY showcase_demo:v1 data
-- =============================================================================
-- BEGIN;
-- DELETE FROM public.posts WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid AND id IN (
--   SELECT p.id FROM public.posts p JOIN public.trades t ON t.id = p.trade_id
--   WHERE t.import_fingerprint LIKE 'showcase_demo:v1:%'
-- );
-- DELETE FROM public.trade_ai_messages m USING public.trades t
--   WHERE m.trade_id = t.id AND t.user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid AND t.import_fingerprint LIKE 'showcase_demo:v1:%';
-- DELETE FROM public.profile_posts WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid AND content LIKE '[showcase_demo:v1]%';
-- DELETE FROM public.achievements WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid AND metadata->>'seed' = 'showcase_demo:v1';
-- DELETE FROM public.account_payout_entries WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid AND note LIKE '[showcase_demo:v1:payouts]%';
-- DELETE FROM public.account_payout_cycles WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid AND note LIKE '[showcase_demo:v1:payouts]%';
-- DELETE FROM public.trader_daily_check_ins WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid AND notes LIKE '[showcase_demo:v1]%';
-- DELETE FROM public.trades WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid AND import_fingerprint LIKE 'showcase_demo:v1:%';
-- DELETE FROM public.accounts WHERE user_id = '3daf15b8-2f5d-48c8-ac98-75bca6c878f4'::uuid AND note LIKE '[showcase_demo:v1]%';
-- COMMIT;
