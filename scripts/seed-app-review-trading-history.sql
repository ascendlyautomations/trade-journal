-- =============================================================================
-- TradeTraxs App Store / demo account — trading history seed (MANUAL RUN ONLY)
-- =============================================================================
--
-- 1) REPLACE THESE PLACEHOLDERS in the DO $$ block (search 00000000-0000-4000-8000):
--      target_user_id    → profiles.id for the demo user
--      target_account_id → existing accounts.id owned by that user
--
-- 2) Configurable date window for this file:
--      START_DATE = 2025-07-28
--      END_DATE   = 2025-09-15
--
-- 3) Tables affected: public.trades, public.trader_daily_check_ins
--
-- 4) Expected row counts: 78 trades, 25 daily check-ins
--
-- 5) Expected performance (net P&L includes round-trip fee assumption in pnl column):
--      Win rate ≈ 62.8% (49 wins / 29 losses / 0 ~breakeven)
--      Total net P&L ≈ $2,676.88
--      Active trade days: 32 across ~7 weeks (Sun–Fri possible; Sat skipped)
--
-- 6) How to run: paste in Supabase SQL editor (service role) or psql, then COMMIT.
--
-- 7) Verify:
--      SELECT count(*), round(sum(pnl)::numeric,2),
--             round(100.0*count(*) filter (where pnl>0)/count(*),1) AS win_pct
--        FROM public.trades
--       WHERE user_id = '<your-user-uuid>'::uuid
--         AND import_fingerprint LIKE 'app_review_seed:v1:trade:%';
--
-- 8) Rollback block at end of file.
--
-- Idempotency: import_fingerprint 'app_review_seed:v1:trade:NNN' / check-in notes prefix.
-- import_source = 'manual' (canonical manual journal inserts; no broker lifecycle ids).
--
-- P&L math (native FuturesInstrumentRegistry): MNQ $2/point/contract, NQ $20/point/contract;
-- points = directional price diff; pnl = points × point_value × contracts − fee assumption.
-- trade_date / session: America/New_York (iOS TradingSessionLabel + web getSession.ts).
--
-- Psychology populated on trades: confidence, emotion, exit_emotion, followed_plan,
-- market_condition, psychology_notes, execution_rating (1–5), timeframe, news_event, rr.
-- Daily check-ins: sleep_hours, sleep_quality, morning_rating, stress_level (1=stressed,
-- 5=calm), energy_level, focus_level, notes.
--
-- Requested but NOT stored as dedicated columns: stop loss, take profit, trade tags,
-- commissions (net fee baked into pnl / notes only), discipline as its own field
-- (use execution_rating), pre-trade vs post-trade beyond emotion/exit_emotion,
-- separate trade_notes / trade_analysis tables, wins/lessons aggregates.
-- mistake_type, trade_type, top_confluences exist on trades (web / bootstrap); native
-- Trade detail UI may not surface all of them yet.
-- =============================================================================

BEGIN;

CREATE TEMP TABLE _app_review_seed_trades ON COMMIT DROP AS
SELECT * FROM (VALUES

('1a7d61ff-5de4-51c8-9d3d-81789e293560'::uuid, 1, '2025-07-29'::date, 'MNQ', 'Long', 2, 22861.3, 22886.3, 25.0, 97.96, '2025-07-29T09:35:00-04:00'::timestamptz, '2025-07-29T10:33:00-04:00'::timestamptz, 'NY', 3480, '58m', 'VWAP Reclaim', 'Good entry but took profit too early.', '2m', 1.26, 3, 'Focused', 'Focused', 3, true, 'Ranging', false, null, 'Day trade', 'Stayed patient after the first loss.', null, 'app_review_seed:v1:trade:001'),
('b5a256ee-6b38-54a0-8322-81ab18ecea5f'::uuid, 2, '2025-07-29'::date, 'MNQ', 'Long', 2, 22872.6, 22890.6, 18.0, 69.96, '2025-07-29T10:05:00-04:00'::timestamptz, '2025-07-29T10:49:00-04:00'::timestamptz, 'NY', 2640, '44m', 'Pullback to 9 EMA', 'Chased the second entry. Should have left it alone.', '5m', 2.62, 5, 'Fearful', 'Confident', 4, true, 'Choppy', false, null, 'Swing scalp', 'Entered before confirmation.', null, 'app_review_seed:v1:trade:002'),
('7e3029c6-108f-56da-8cfe-7783c1d26daa'::uuid, 3, '2025-07-30'::date, 'MNQ', 'Long', 2, 22883.9, 22895.9, 12.0, 45.96, '2025-07-30T11:18:00-04:00'::timestamptz, '2025-07-30T12:33:00-04:00'::timestamptz, 'NY', 4500, '1h 15m', 'Supply/Demand Fade', 'Stayed patient after the first loss.', '15m', 1.89, 2, 'FOMO', 'Confident', 3, true, 'High Volume', false, null, 'Scalp', 'Revenge click after the stop — noted for review.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:003'),
('0f704b71-66d2-572f-8f45-b1e2d311e01b'::uuid, 4, '2025-07-30'::date, 'NQ', 'Long', 1, 22895.2, 22907.2, 12.0, 235.96, '2025-07-30T12:08:00-04:00'::timestamptz, '2025-07-30T12:19:00-04:00'::timestamptz, 'NY', 660, '11m', 'Trend Continuation', 'Clean setup. Followed the plan.', '1m', 2.43, 5, 'Frustrated', 'Confident', 5, true, 'Volatile', false, null, 'Day trade', 'Waited for the pullback instead of chasing.', null, 'app_review_seed:v1:trade:004'),
('ff67008c-07b7-5339-bd87-9e2033966c98'::uuid, 5, '2025-07-30'::date, 'MNQ', 'Short', 2, 22921.5, 22896.5, 25.0, 97.96, '2025-07-30T13:22:00-04:00'::timestamptz, '2025-07-30T14:06:00-04:00'::timestamptz, 'NY', 2640, '44m', 'Failed Breakout', 'Overtraded after giving back the morning profit.', '2m', 2.07, 5, 'Hesitant', 'Calm', 5, true, 'Strong Trend', false, null, 'Swing scalp', 'Stayed patient after the first loss.', null, 'app_review_seed:v1:trade:005'),
('4305e6b0-2880-592f-80fa-8d98ce99004b'::uuid, 6, '2025-07-30'::date, 'MNQ', 'Long', 2, 22917.8, 22903.8, -14.0, -58.04, '2025-07-30T14:05:00-04:00'::timestamptz, '2025-07-30T14:09:00-04:00'::timestamptz, 'NY', 240, '4m', 'Opening Range Breakout', 'Entered before confirmation.', '5m', -1.11, 2, 'Fearful', 'Frustrated', 3, true, 'Low Volume', false, 'Moved stop', 'Scalp', 'Entered before confirmation.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:006'),
('d51876b0-5f51-5763-ba54-80428b3d2a07'::uuid, 7, '2025-07-30'::date, 'MNQ', 'Long', 2, 22929.1, 22947.1, 18.0, 69.96, '2025-07-30T14:48:00-04:00'::timestamptz, '2025-07-30T15:32:00-04:00'::timestamptz, 'NY', 2640, '44m', 'VWAP Reclaim', 'Cut it when the setup invalidated.', '15m', 1.28, 2, 'Confident', 'Focused', 5, true, 'Trending', false, null, 'Day trade', 'Revenge click after the stop — noted for review.', 'VWAP, prior day high', 'app_review_seed:v1:trade:007'),
('e62b1af4-028a-54cb-8a3f-a7181bbff64a'::uuid, 8, '2025-07-30'::date, 'NQ', 'Short', 1, 22955.4, 22949.4, 6.0, 115.96, '2025-07-30T15:25:00-04:00'::timestamptz, '2025-07-30T16:40:00-04:00'::timestamptz, 'NY', 4500, '1h 15m', 'Pullback to 9 EMA', 'Good trade, execution could have been better.', '1m', 2.37, 2, 'Calm', 'Calm', 5, true, 'Ranging', false, null, 'Swing scalp', 'Waited for the pullback instead of chasing.', null, 'app_review_seed:v1:trade:008'),
('36da4c1b-b8e6-52f6-a9e9-daa4b3395020'::uuid, 9, '2025-07-31'::date, 'MNQ', 'Long', 2, 22951.7, 22966.7, 15.0, 57.96, '2025-07-31T09:35:00-04:00'::timestamptz, '2025-07-31T09:46:00-04:00'::timestamptz, 'NY', 660, '11m', 'Supply/Demand Fade', 'Revenge click after the stop — noted for review.', '2m', 1.67, 3, 'Focused', 'Focused', 5, true, 'Choppy', false, null, 'Scalp', 'Stayed patient after the first loss.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:009'),
('06fd992d-de09-550a-b178-354d8c052fc7'::uuid, 10, '2025-07-31'::date, 'MNQ', 'Short', 2, 22978.0, 22970.0, 8.0, 29.96, '2025-07-31T10:05:00-04:00'::timestamptz, '2025-07-31T10:36:00-04:00'::timestamptz, 'NY', 1860, '31m', 'Trend Continuation', 'Partial at VWAP, runner stopped at BE.', '5m', 1.88, 2, 'Fearful', 'Calm', 4, true, 'High Volume', false, null, 'Day trade', 'Entered before confirmation.', null, 'app_review_seed:v1:trade:010'),
('ea8d88be-729d-58fd-8368-43269fce92ed'::uuid, 11, '2025-08-01'::date, 'MNQ', 'Long', 3, 22974.3, 22989.3, 15.0, 87.96, '2025-08-01T10:42:00-04:00'::timestamptz, '2025-08-01T10:46:00-04:00'::timestamptz, 'NY', 240, '4m', 'Failed Breakout', 'Skipped first signal, took the second — worked out.', '15m', 1.43, 2, 'FOMO', 'Focused', 3, true, 'Volatile', false, null, 'Swing scalp', 'Revenge click after the stop — noted for review.', null, 'app_review_seed:v1:trade:011'),
('b85181b5-9d31-5e50-bc9c-48b02fa3cb97'::uuid, 12, '2025-08-03'::date, 'NQ', 'Long', 1, 22985.6, 22985.85, 0.25, 0.96, '2025-08-03T13:22:00-04:00'::timestamptz, '2025-08-03T14:20:00-04:00'::timestamptz, 'NY', 3480, '58m', 'Opening Range Breakout', 'Waited for the pullback instead of chasing.', '1m', 0.25, 2, 'FOMO', 'Calm', 3, true, 'Strong Trend', false, null, 'Scalp', 'Waited for the pullback instead of chasing.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:012'),
('aba3861d-f0af-5544-b6d8-6cb6dc98acf8'::uuid, 13, '2025-08-04'::date, 'MNQ', 'Long', 2, 22996.9, 22976.9, -20.0, -82.04, '2025-08-04T14:48:00-04:00'::timestamptz, '2025-08-04T14:59:00-04:00'::timestamptz, 'NY', 660, '11m', 'VWAP Reclaim', 'Good entry but took profit too early.', '2m', -0.78, 4, 'FOMO', 'Hesitant', 3, true, 'Low Volume', false, 'Revenge trade', 'Day trade', 'Stayed patient after the first loss.', null, 'app_review_seed:v1:trade:013'),
('bfb753e4-51f8-572d-a622-274094c20271'::uuid, 14, '2025-08-04'::date, 'MNQ', 'Long', 2, 23008.2, 23033.2, 25.0, 97.96, '2025-08-04T15:25:00-04:00'::timestamptz, '2025-08-04T15:41:00-04:00'::timestamptz, 'NY', 960, '16m', 'Pullback to 9 EMA', 'Chased the second entry. Should have left it alone.', '5m', 2.67, 3, 'Overconfident', 'Calm', 5, true, 'Trending', false, null, 'Swing scalp', 'Entered before confirmation.', 'VWAP, prior day high', 'app_review_seed:v1:trade:014'),
('c1edb190-3837-5655-89f1-ed40558e20a3'::uuid, 15, '2025-08-04'::date, 'MNQ', 'Short', 2, 23034.5, 23046.5, -12.0, -50.04, '2025-08-04T09:12:00-04:00'::timestamptz, '2025-08-04T09:43:00-04:00'::timestamptz, 'NY', 1860, '31m', 'Supply/Demand Fade', 'Stayed patient after the first loss.', '15m', -0.96, 1, 'FOMO', 'Frustrated', 1, false, 'Ranging', false, 'Early entry', 'Scalp', 'Revenge click after the stop — noted for review.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:015'),
('cbf8d1a3-4c12-5788-b433-6c3c05aa22db'::uuid, 16, '2025-08-04'::date, 'NQ', 'Long', 1, 23030.8, 23025.8, -5.0, -104.04, '2025-08-04T09:35:00-04:00'::timestamptz, '2025-08-04T09:39:00-04:00'::timestamptz, 'NY', 240, '4m', 'Trend Continuation', 'Clean setup. Followed the plan.', '1m', -1.05, 2, 'FOMO', 'Frustrated', 3, true, 'Choppy', false, 'Moved stop', 'Day trade', 'Waited for the pullback instead of chasing.', null, 'app_review_seed:v1:trade:016'),
('3dd6ea4a-f565-5099-9720-9dd0be2858b7'::uuid, 17, '2025-08-05'::date, 'MNQ', 'Short', 2, 23057.1, 23047.1, 10.0, 37.96, '2025-08-05T10:42:00-04:00'::timestamptz, '2025-08-05T10:46:00-04:00'::timestamptz, 'NY', 240, '4m', 'Failed Breakout', 'Overtraded after giving back the morning profit.', '2m', 1.41, 2, 'Focused', 'Confident', 4, true, 'High Volume', false, null, 'Swing scalp', 'Stayed patient after the first loss.', null, 'app_review_seed:v1:trade:017'),
('7e00442f-98c7-5bdb-8a32-fb7797752d3b'::uuid, 18, '2025-08-05'::date, 'MNQ', 'Long', 2, 23053.4, 23039.4, -14.0, -58.04, '2025-08-05T11:18:00-04:00'::timestamptz, '2025-08-05T11:34:00-04:00'::timestamptz, 'NY', 960, '16m', 'Opening Range Breakout', 'Entered before confirmation.', '5m', -0.87, 1, 'FOMO', 'Fearful', 3, true, 'Volatile', false, 'Revenge trade', 'Scalp', 'Entered before confirmation.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:018'),
('7e70a9c5-c308-53ae-888d-db38c2906ede'::uuid, 19, '2025-08-06'::date, 'MNQ', 'Short', 2, 23079.7, 23049.7, 30.0, 117.96, '2025-08-06T13:22:00-04:00'::timestamptz, '2025-08-06T13:38:00-04:00'::timestamptz, 'NY', 960, '16m', 'VWAP Reclaim', 'Cut it when the setup invalidated.', '15m', 2.41, 5, 'FOMO', 'Confident', 3, true, 'Strong Trend', false, null, 'Day trade', 'Revenge click after the stop — noted for review.', null, 'app_review_seed:v1:trade:019'),
('6a37c98e-3c11-5d54-851b-3e75bb3bda5e'::uuid, 20, '2025-08-06'::date, 'NQ', 'Long', 1, 23076.0, 23073.0, -3.0, -64.04, '2025-08-06T14:05:00-04:00'::timestamptz, '2025-08-06T14:49:00-04:00'::timestamptz, 'NY', 2640, '44m', 'Pullback to 9 EMA', 'Good trade, execution could have been better.', '1m', -0.91, 4, 'Frustrated', 'Fearful', 2, false, 'Low Volume', false, 'Early entry', 'Swing scalp', 'Waited for the pullback instead of chasing.', null, 'app_review_seed:v1:trade:020'),
('36ea466b-2acf-58ce-8c54-4ebd5c037f91'::uuid, 21, '2025-08-06'::date, 'MNQ', 'Long', 2, 23087.3, 23101.3, 14.0, 53.96, '2025-08-06T14:48:00-04:00'::timestamptz, '2025-08-06T14:52:00-04:00'::timestamptz, 'NY', 240, '4m', 'Supply/Demand Fade', 'Revenge click after the stop — noted for review.', '2m', 1.72, 4, 'Hesitant', 'Confident', 3, true, 'Trending', false, null, 'Scalp', 'Stayed patient after the first loss.', 'VWAP, prior day high', 'app_review_seed:v1:trade:021'),
('af80219e-8c09-5d8c-8c5f-5c7699241b05'::uuid, 22, '2025-08-06'::date, 'MNQ', 'Short', 3, 23113.6, 23098.6, 15.0, 87.96, '2025-08-06T15:25:00-04:00'::timestamptz, '2025-08-06T15:41:00-04:00'::timestamptz, 'NY', 960, '16m', 'Trend Continuation', 'Partial at VWAP, runner stopped at BE.', '5m', 1.97, 3, 'Overconfident', 'Confident', 4, true, 'Ranging', false, null, 'Day trade', 'Entered before confirmation.', null, 'app_review_seed:v1:trade:022'),
('bdc230df-b2a6-5485-9c85-73bf72b05773'::uuid, 23, '2025-08-08'::date, 'MNQ', 'Short', 2, 23124.9, 23152.9, -28.0, -114.04, '2025-08-08T10:05:00-04:00'::timestamptz, '2025-08-08T11:03:00-04:00'::timestamptz, 'NY', 3480, '58m', 'Failed Breakout', 'Skipped first signal, took the second — worked out.', '15m', -0.85, 1, 'Frustrated', 'Frustrated', 2, true, 'Choppy', false, 'Revenge trade', 'Swing scalp', 'Revenge click after the stop — noted for review.', null, 'app_review_seed:v1:trade:023'),
('689a83bc-0c38-5331-afca-30442a640300'::uuid, 24, '2025-08-08'::date, 'NQ', 'Long', 1, 23121.2, 23133.2, 12.0, 235.96, '2025-08-08T10:42:00-04:00'::timestamptz, '2025-08-08T11:57:00-04:00'::timestamptz, 'NY', 4500, '1h 15m', 'Opening Range Breakout', 'Waited for the pullback instead of chasing.', '1m', 2.5, 2, 'Calm', 'Confident', 3, true, 'High Volume', false, null, 'Scalp', 'Waited for the pullback instead of chasing.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:024'),
('2a861216-cefd-5514-ba24-c9bd8c12bc0c'::uuid, 25, '2025-08-08'::date, 'MNQ', 'Long', 2, 22852.5, 22877.5, 25.0, 97.96, '2025-08-08T11:18:00-04:00'::timestamptz, '2025-08-08T12:16:00-04:00'::timestamptz, 'NY', 3480, '58m', 'VWAP Reclaim', 'Good entry but took profit too early.', '2m', 1.87, 5, 'Focused', 'Confident', 3, true, 'Volatile', false, null, 'Day trade', 'Stayed patient after the first loss.', null, 'app_review_seed:v1:trade:025'),
('c22ad425-3ee2-5421-9265-2d922bbd38b3'::uuid, 26, '2025-08-11'::date, 'MNQ', 'Short', 2, 22878.8, 22890.8, -12.0, -50.04, '2025-08-11T14:48:00-04:00'::timestamptz, '2025-08-11T14:52:00-04:00'::timestamptz, 'NY', 240, '4m', 'Pullback to 9 EMA', 'Chased the second entry. Should have left it alone.', '5m', -1.29, 3, 'Fearful', 'Hesitant', 2, true, 'Strong Trend', false, 'Moved stop', 'Swing scalp', 'Entered before confirmation.', null, 'app_review_seed:v1:trade:026'),
('bc43ac9e-4012-528a-8f6f-643cc39b9f12'::uuid, 27, '2025-08-11'::date, 'MNQ', 'Long', 2, 22875.1, 22859.1, -16.0, -66.04, '2025-08-11T15:25:00-04:00'::timestamptz, '2025-08-11T16:40:00-04:00'::timestamptz, 'NY', 4500, '1h 15m', 'Supply/Demand Fade', 'Stayed patient after the first loss.', '15m', -1.1, 1, 'Fearful', 'Frustrated', 1, true, 'Low Volume', false, 'Oversized', 'Scalp', 'Revenge click after the stop — noted for review.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:027'),
('2db8854f-7db0-57a1-8139-e0523acabf91'::uuid, 28, '2025-08-12'::date, 'NQ', 'Short', 1, 22901.4, 22897.4, 4.0, 75.96, '2025-08-12T09:35:00-04:00'::timestamptz, '2025-08-12T10:50:00-04:00'::timestamptz, 'NY', 4500, '1h 15m', 'Trend Continuation', 'Clean setup. Followed the plan.', '1m', 1.11, 4, 'Frustrated', 'Confident', 3, true, 'Trending', false, null, 'Day trade', 'Waited for the pullback instead of chasing.', 'VWAP, prior day high', 'app_review_seed:v1:trade:028'),
('79bdebc9-56cf-597d-a09e-24034f075bac'::uuid, 29, '2025-08-12'::date, 'MNQ', 'Long', 2, 22897.7, 22883.7, -14.0, -58.04, '2025-08-12T10:05:00-04:00'::timestamptz, '2025-08-12T11:03:00-04:00'::timestamptz, 'NY', 3480, '58m', 'Failed Breakout', 'Overtraded after giving back the morning profit.', '2m', -1.0, 2, 'Frustrated', 'Frustrated', 1, true, 'Ranging', true, 'Ignored plan', 'Swing scalp', 'Stayed patient after the first loss.', null, 'app_review_seed:v1:trade:029'),
('d3f92850-bb4f-5560-af33-7dbb6b954f89'::uuid, 30, '2025-08-13'::date, 'MNQ', 'Short', 2, 22924.0, 22914.0, 10.0, 37.96, '2025-08-13T11:18:00-04:00'::timestamptz, '2025-08-13T11:25:00-04:00'::timestamptz, 'NY', 420, '7m', 'Opening Range Breakout', 'Entered before confirmation.', '5m', 2.22, 3, 'Overconfident', 'Confident', 4, true, 'Choppy', false, null, 'Scalp', 'Entered before confirmation.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:030'),
('3856fdf9-737a-5aeb-8ab4-c8d9f36b84ab'::uuid, 31, '2025-08-13'::date, 'MNQ', 'Long', 2, 22920.3, 22906.3, -14.0, -58.04, '2025-08-13T12:08:00-04:00'::timestamptz, '2025-08-13T12:24:00-04:00'::timestamptz, 'NY', 960, '16m', 'VWAP Reclaim', 'Cut it when the setup invalidated.', '15m', -1.05, 1, 'Frustrated', 'Hesitant', 3, true, 'High Volume', false, 'Moved stop', 'Day trade', 'Revenge click after the stop — noted for review.', null, 'app_review_seed:v1:trade:031'),
('12d82fc4-dfb8-5cf2-9c48-ccdeedc68aa6'::uuid, 32, '2025-08-14'::date, 'NQ', 'Short', 1, 22946.6, 22956.6, -10.0, -204.04, '2025-08-14T14:05:00-04:00'::timestamptz, '2025-08-14T15:20:00-04:00'::timestamptz, 'NY', 4500, '1h 15m', 'Pullback to 9 EMA', 'Good trade, execution could have been better.', '1m', -0.89, 3, 'Fearful', 'Frustrated', 1, true, 'Volatile', false, 'Oversized', 'Swing scalp', 'Waited for the pullback instead of chasing.', null, 'app_review_seed:v1:trade:032'),
('16f0141f-3bcb-55fe-b720-9c18f5a21708'::uuid, 33, '2025-08-14'::date, 'MNQ', 'Long', 2, 22942.9, 22932.9, -10.0, -42.04, '2025-08-14T14:48:00-04:00'::timestamptz, '2025-08-14T15:32:00-04:00'::timestamptz, 'NY', 2640, '44m', 'Supply/Demand Fade', 'Revenge click after the stop — noted for review.', '2m', -0.78, 2, 'Frustrated', 'Frustrated', 2, true, 'Strong Trend', false, 'Revenge trade', 'Scalp', 'Stayed patient after the first loss.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:033'),
('262821c9-219b-5353-a585-fb344b4aa009'::uuid, 34, '2025-08-17'::date, 'MNQ', 'Long', 2, 22954.2, 22942.2, -12.0, -50.04, '2025-08-17T10:05:00-04:00'::timestamptz, '2025-08-17T10:12:00-04:00'::timestamptz, 'NY', 420, '7m', 'Trend Continuation', 'Partial at VWAP, runner stopped at BE.', '5m', -0.74, 2, 'Fearful', 'Frustrated', 3, true, 'Low Volume', false, 'Ignored plan', 'Day trade', 'Entered before confirmation.', null, 'app_review_seed:v1:trade:034'),
('efce474e-f3cc-59a1-abaf-94851a3ae609'::uuid, 35, '2025-08-17'::date, 'MNQ', 'Short', 2, 22980.5, 22960.5, 20.0, 77.96, '2025-08-17T10:42:00-04:00'::timestamptz, '2025-08-17T10:49:00-04:00'::timestamptz, 'NY', 420, '7m', 'Failed Breakout', 'Skipped first signal, took the second — worked out.', '15m', 2.58, 4, 'FOMO', 'Confident', 4, true, 'Trending', false, null, 'Swing scalp', 'Revenge click after the stop — noted for review.', 'VWAP, prior day high', 'app_review_seed:v1:trade:035'),
('83506651-40a8-52d0-a1cb-413b578f4c7a'::uuid, 36, '2025-08-18'::date, 'NQ', 'Long', 1, 22976.8, 22984.8, 8.0, 155.96, '2025-08-18T12:08:00-04:00'::timestamptz, '2025-08-18T13:23:00-04:00'::timestamptz, 'NY', 4500, '1h 15m', 'Opening Range Breakout', 'Waited for the pullback instead of chasing.', '1m', 2.27, 2, 'Frustrated', 'Focused', 5, true, 'Ranging', false, null, 'Scalp', 'Waited for the pullback instead of chasing.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:036'),
('31eff7b4-2503-5583-9b09-4f550f173b12'::uuid, 37, '2025-08-18'::date, 'MNQ', 'Short', 2, 23003.1, 22985.1, 18.0, 69.96, '2025-08-18T13:22:00-04:00'::timestamptz, '2025-08-18T13:29:00-04:00'::timestamptz, 'NY', 420, '7m', 'VWAP Reclaim', 'Good entry but took profit too early.', '2m', 2.69, 3, 'Hesitant', 'Confident', 4, true, 'Choppy', false, null, 'Day trade', 'Stayed patient after the first loss.', null, 'app_review_seed:v1:trade:037'),
('da8f00b1-1bc6-55ca-a45a-bf283a13209b'::uuid, 38, '2025-08-18'::date, 'MNQ', 'Long', 2, 22999.4, 22993.4, -6.0, -26.04, '2025-08-18T14:05:00-04:00'::timestamptz, '2025-08-18T15:20:00-04:00'::timestamptz, 'NY', 4500, '1h 15m', 'Pullback to 9 EMA', 'Chased the second entry. Should have left it alone.', '5m', -0.79, 3, 'FOMO', 'Fearful', 3, true, 'High Volume', false, 'Revenge trade', 'Swing scalp', 'Entered before confirmation.', null, 'app_review_seed:v1:trade:038'),
('9c2443e6-4f9b-5aba-93ee-4c398ef941bf'::uuid, 39, '2025-08-18'::date, 'MNQ', 'Long', 2, 23010.7, 23030.7, 20.0, 77.96, '2025-08-18T14:48:00-04:00'::timestamptz, '2025-08-18T15:04:00-04:00'::timestamptz, 'NY', 960, '16m', 'Supply/Demand Fade', 'Stayed patient after the first loss.', '15m', 2.24, 4, 'Confident', 'Calm', 5, true, 'Volatile', false, null, 'Scalp', 'Revenge click after the stop — noted for review.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:039'),
('cbb3cb5e-20fc-50ee-a339-35b2be66cf05'::uuid, 40, '2025-08-18'::date, 'NQ', 'Short', 1, 23037.0, 23031.0, 6.0, 115.96, '2025-08-18T15:25:00-04:00'::timestamptz, '2025-08-18T15:29:00-04:00'::timestamptz, 'NY', 240, '4m', 'Trend Continuation', 'Clean setup. Followed the plan.', '1m', 1.17, 5, 'Calm', 'Confident', 4, true, 'Strong Trend', false, null, 'Day trade', 'Waited for the pullback instead of chasing.', null, 'app_review_seed:v1:trade:040'),
('24353178-5479-5deb-8886-dbf200e202af'::uuid, 41, '2025-08-20'::date, 'MNQ', 'Short', 2, 23048.3, 23054.3, -6.0, -26.04, '2025-08-20T10:05:00-04:00'::timestamptz, '2025-08-20T10:36:00-04:00'::timestamptz, 'NY', 1860, '31m', 'Failed Breakout', 'Overtraded after giving back the morning profit.', '2m', -1.16, 3, 'Overconfident', 'Fearful', 1, true, 'Low Volume', false, 'Moved stop', 'Swing scalp', 'Stayed patient after the first loss.', null, 'app_review_seed:v1:trade:041'),
('217fe149-8496-506f-bb92-fc5fc129eb4a'::uuid, 42, '2025-08-20'::date, 'MNQ', 'Long', 2, 23044.6, 23079.6, 35.0, 137.96, '2025-08-20T10:42:00-04:00'::timestamptz, '2025-08-20T11:57:00-04:00'::timestamptz, 'NY', 4500, '1h 15m', 'Opening Range Breakout', 'Entered before confirmation.', '5m', 1.02, 2, 'Fearful', 'Confident', 5, true, 'Trending', false, null, 'Scalp', 'Entered before confirmation.', 'VWAP, prior day high', 'app_review_seed:v1:trade:042'),
('961db3e5-bdd4-5249-b753-fb51eff4fb79'::uuid, 43, '2025-08-20'::date, 'MNQ', 'Long', 2, 23055.9, 23041.9, -14.0, -58.04, '2025-08-20T11:18:00-04:00'::timestamptz, '2025-08-20T11:22:00-04:00'::timestamptz, 'NY', 240, '4m', 'VWAP Reclaim', 'Cut it when the setup invalidated.', '15m', -1.2, 2, 'FOMO', 'Frustrated', 2, true, 'Ranging', false, 'Revenge trade', 'Day trade', 'Revenge click after the stop — noted for review.', null, 'app_review_seed:v1:trade:043'),
('02dc201a-5e60-5da1-b9e2-af743c278071'::uuid, 44, '2025-08-20'::date, 'NQ', 'Short', 1, 23082.2, 23087.2, -5.0, -104.04, '2025-08-20T12:08:00-04:00'::timestamptz, '2025-08-20T12:39:00-04:00'::timestamptz, 'NY', 1860, '31m', 'Pullback to 9 EMA', 'Good trade, execution could have been better.', '1m', -1.24, 1, 'FOMO', 'Fearful', 2, true, 'Choppy', false, 'Ignored plan', 'Swing scalp', 'Waited for the pullback instead of chasing.', null, 'app_review_seed:v1:trade:044'),
('3f52fe7c-773e-577b-bfeb-8f77a5babfa1'::uuid, 45, '2025-08-22'::date, 'MNQ', 'Short', 2, 23093.5, 23101.5, -8.0, -34.04, '2025-08-22T14:48:00-04:00'::timestamptz, '2025-08-22T14:55:00-04:00'::timestamptz, 'NY', 420, '7m', 'Supply/Demand Fade', 'Revenge click after the stop — noted for review.', '2m', -0.91, 1, 'FOMO', 'Frustrated', 1, false, 'High Volume', false, 'Early entry', 'Scalp', 'Stayed patient after the first loss.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:045'),
('0fb05a9b-8abd-5cf7-afa2-33f2bbb921fd'::uuid, 46, '2025-08-22'::date, 'MNQ', 'Long', 2, 23089.8, 23114.8, 25.0, 97.96, '2025-08-22T15:25:00-04:00'::timestamptz, '2025-08-22T15:29:00-04:00'::timestamptz, 'NY', 240, '4m', 'Trend Continuation', 'Partial at VWAP, runner stopped at BE.', '5m', 1.32, 4, 'Overconfident', 'Focused', 4, true, 'Volatile', false, null, 'Day trade', 'Entered before confirmation.', null, 'app_review_seed:v1:trade:046'),
('7a72c362-48bc-50b2-b515-fdae9c92336b'::uuid, 47, '2025-08-25'::date, 'MNQ', 'Long', 2, 23101.1, 23116.1, 15.0, 57.96, '2025-08-25T10:42:00-04:00'::timestamptz, '2025-08-25T11:04:00-04:00'::timestamptz, 'NY', 1320, '22m', 'Failed Breakout', 'Skipped first signal, took the second — worked out.', '15m', 1.29, 2, 'Confident', 'Confident', 4, true, 'Strong Trend', false, null, 'Swing scalp', 'Revenge click after the stop — noted for review.', null, 'app_review_seed:v1:trade:047'),
('972f3396-2caf-5734-ab4b-6b66ad7ad857'::uuid, 48, '2025-08-25'::date, 'NQ', 'Short', 1, 23127.4, 23119.4, 8.0, 155.96, '2025-08-25T11:18:00-04:00'::timestamptz, '2025-08-25T11:34:00-04:00'::timestamptz, 'NY', 960, '16m', 'Opening Range Breakout', 'Waited for the pullback instead of chasing.', '1m', 1.36, 5, 'Calm', 'Calm', 4, true, 'Low Volume', false, null, 'Scalp', 'Waited for the pullback instead of chasing.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:048'),
('4c5998ae-cbe5-5c89-830c-7f8f0b0c0c44'::uuid, 49, '2025-08-25'::date, 'MNQ', 'Long', 2, 23123.7, 23138.7, 15.0, 57.96, '2025-08-25T12:08:00-04:00'::timestamptz, '2025-08-25T12:24:00-04:00'::timestamptz, 'NY', 960, '16m', 'VWAP Reclaim', 'Good entry but took profit too early.', '2m', 1.04, 3, 'Focused', 'Calm', 4, true, 'Trending', false, null, 'Day trade', 'Stayed patient after the first loss.', 'VWAP, prior day high', 'app_review_seed:v1:trade:049'),
('ed40c884-7b62-55b1-857e-cc9975a72912'::uuid, 50, '2025-08-26'::date, 'MNQ', 'Short', 2, 22870.0, 22880.0, -10.0, -42.04, '2025-08-26T14:05:00-04:00'::timestamptz, '2025-08-26T14:12:00-04:00'::timestamptz, 'NY', 420, '7m', 'Pullback to 9 EMA', 'Chased the second entry. Should have left it alone.', '5m', -1.28, 3, 'Overconfident', 'Fearful', 2, false, 'Ranging', false, 'Early entry', 'Swing scalp', 'Entered before confirmation.', null, 'app_review_seed:v1:trade:050'),
('71cf7b82-a50d-5251-b594-b1f2218dd193'::uuid, 51, '2025-08-28'::date, 'MNQ', 'Short', 2, 22881.3, 22901.3, -20.0, -82.04, '2025-08-28T09:12:00-04:00'::timestamptz, '2025-08-28T10:27:00-04:00'::timestamptz, 'NY', 4500, '1h 15m', 'Supply/Demand Fade', 'Stayed patient after the first loss.', '15m', -0.9, 1, 'FOMO', 'Fearful', 2, true, 'Choppy', false, 'Moved stop', 'Scalp', 'Revenge click after the stop — noted for review.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:051'),
('ac2b055d-e8c3-570d-8bf6-930ebf567a87'::uuid, 52, '2025-08-29'::date, 'NQ', 'Long', 1, 22877.6, 22883.6, 6.0, 115.96, '2025-08-29T10:05:00-04:00'::timestamptz, '2025-08-29T10:09:00-04:00'::timestamptz, 'NY', 240, '4m', 'Trend Continuation', 'Clean setup. Followed the plan.', '1m', 1.2, 5, 'Frustrated', 'Focused', 4, true, 'High Volume', false, null, 'Day trade', 'Waited for the pullback instead of chasing.', null, 'app_review_seed:v1:trade:052'),
('aecd65b2-dc8c-59a8-bb18-d9b427ae4ef6'::uuid, 53, '2025-08-31'::date, 'MNQ', 'Long', 2, 22888.9, 22908.9, 20.0, 77.96, '2025-08-31T12:08:00-04:00'::timestamptz, '2025-08-31T12:52:00-04:00'::timestamptz, 'NY', 2640, '44m', 'Failed Breakout', 'Overtraded after giving back the morning profit.', '2m', 2.09, 2, 'Hesitant', 'Focused', 4, true, 'Volatile', false, null, 'Swing scalp', 'Stayed patient after the first loss.', null, 'app_review_seed:v1:trade:053'),
('89561d92-56dd-54ea-9561-a29c18bd62ff'::uuid, 54, '2025-09-01'::date, 'MNQ', 'Long', 2, 22900.2, 22915.2, 15.0, 57.96, '2025-09-01T13:22:00-04:00'::timestamptz, '2025-09-01T13:44:00-04:00'::timestamptz, 'NY', 1320, '22m', 'Opening Range Breakout', 'Entered before confirmation.', '5m', 1.08, 5, 'Overconfident', 'Focused', 3, true, 'Strong Trend', false, null, 'Scalp', 'Entered before confirmation.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:054'),
('cedcb104-0b5f-5ab7-90a4-d15f77328299'::uuid, 55, '2025-09-01'::date, 'MNQ', 'Long', 3, 22911.5, 22926.5, 15.0, 87.96, '2025-09-01T14:05:00-04:00'::timestamptz, '2025-09-01T14:36:00-04:00'::timestamptz, 'NY', 1860, '31m', 'VWAP Reclaim', 'Cut it when the setup invalidated.', '15m', 1.78, 4, 'Confident', 'Calm', 5, true, 'Low Volume', false, null, 'Day trade', 'Revenge click after the stop — noted for review.', null, 'app_review_seed:v1:trade:055'),
('785917a5-8951-52fc-801c-7e0e45e87f45'::uuid, 56, '2025-09-02'::date, 'NQ', 'Long', 1, 22922.8, 22912.8, -10.0, -204.04, '2025-09-02T15:25:00-04:00'::timestamptz, '2025-09-02T15:32:00-04:00'::timestamptz, 'NY', 420, '7m', 'Pullback to 9 EMA', 'Good trade, execution could have been better.', '1m', -1.13, 3, 'Fearful', 'Fearful', 3, true, 'Trending', false, 'Moved stop', 'Swing scalp', 'Waited for the pullback instead of chasing.', 'VWAP, prior day high', 'app_review_seed:v1:trade:056'),
('84896524-2313-53f5-a301-ff806ae2601d'::uuid, 57, '2025-09-03'::date, 'MNQ', 'Short', 2, 22949.1, 22924.1, 25.0, 97.96, '2025-09-03T09:35:00-04:00'::timestamptz, '2025-09-03T10:06:00-04:00'::timestamptz, 'NY', 1860, '31m', 'Supply/Demand Fade', 'Revenge click after the stop — noted for review.', '2m', 1.72, 4, 'Focused', 'Confident', 5, true, 'Ranging', false, null, 'Scalp', 'Stayed patient after the first loss.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:057'),
('baa75f46-55bd-5ea1-9545-6dd0c4db3463'::uuid, 58, '2025-09-03'::date, 'MNQ', 'Long', 2, 22945.4, 22937.4, -8.0, -34.04, '2025-09-03T10:05:00-04:00'::timestamptz, '2025-09-03T10:49:00-04:00'::timestamptz, 'NY', 2640, '44m', 'Trend Continuation', 'Partial at VWAP, runner stopped at BE.', '5m', -1.1, 4, 'FOMO', 'Fearful', 3, true, 'Choppy', true, 'Revenge trade', 'Day trade', 'Entered before confirmation.', null, 'app_review_seed:v1:trade:058'),
('a25ba2f6-e2d7-573e-8ab4-14ed6463600f'::uuid, 59, '2025-09-03'::date, 'MNQ', 'Long', 2, 22956.7, 22942.7, -14.0, -58.04, '2025-09-03T10:42:00-04:00'::timestamptz, '2025-09-03T11:04:00-04:00'::timestamptz, 'NY', 1320, '22m', 'Failed Breakout', 'Skipped first signal, took the second — worked out.', '15m', -0.94, 1, 'Fearful', 'Frustrated', 2, true, 'High Volume', false, 'Ignored plan', 'Swing scalp', 'Revenge click after the stop — noted for review.', null, 'app_review_seed:v1:trade:059'),
('63133051-b9c4-59b7-a004-13910df21435'::uuid, 60, '2025-09-05'::date, 'NQ', 'Long', 1, 22968.0, 22976.0, 8.0, 155.96, '2025-09-05T13:22:00-04:00'::timestamptz, '2025-09-05T13:53:00-04:00'::timestamptz, 'NY', 1860, '31m', 'Opening Range Breakout', 'Waited for the pullback instead of chasing.', '1m', 1.84, 5, 'Frustrated', 'Confident', 5, true, 'Volatile', false, null, 'Scalp', 'Waited for the pullback instead of chasing.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:060'),
('96d4d06a-0dc4-588c-bf65-7a7fb2e54d62'::uuid, 61, '2025-09-05'::date, 'MNQ', 'Short', 2, 22994.3, 23008.3, -14.0, -58.04, '2025-09-05T14:05:00-04:00'::timestamptz, '2025-09-05T15:03:00-04:00'::timestamptz, 'NY', 3480, '58m', 'VWAP Reclaim', 'Good entry but took profit too early.', '2m', -1.18, 2, 'Frustrated', 'Hesitant', 3, true, 'Strong Trend', false, 'Moved stop', 'Day trade', 'Stayed patient after the first loss.', null, 'app_review_seed:v1:trade:061'),
('c4d3be7a-3b2e-5a12-b422-07de9ae25b20'::uuid, 62, '2025-09-05'::date, 'MNQ', 'Long', 2, 22990.6, 23010.6, 20.0, 77.96, '2025-09-05T14:48:00-04:00'::timestamptz, '2025-09-05T14:55:00-04:00'::timestamptz, 'NY', 420, '7m', 'Pullback to 9 EMA', 'Chased the second entry. Should have left it alone.', '5m', 2.47, 3, 'Overconfident', 'Calm', 5, true, 'Low Volume', false, null, 'Swing scalp', 'Entered before confirmation.', null, 'app_review_seed:v1:trade:062'),
('c0b84d28-08d2-59ed-8be2-4155ea7df73c'::uuid, 63, '2025-09-05'::date, 'MNQ', 'Long', 2, 23001.9, 23022.9, 21.0, 81.96, '2025-09-05T15:25:00-04:00'::timestamptz, '2025-09-05T15:41:00-04:00'::timestamptz, 'NY', 960, '16m', 'Supply/Demand Fade', 'Stayed patient after the first loss.', '15m', 1.27, 2, 'Confident', 'Calm', 3, true, 'Trending', false, null, 'Scalp', 'Revenge click after the stop — noted for review.', 'VWAP, prior day high', 'app_review_seed:v1:trade:063'),
('2a658fc8-c8b5-510a-b5d8-484f4e587368'::uuid, 64, '2025-09-09'::date, 'NQ', 'Long', 1, 23013.2, 23005.2, -8.0, -164.04, '2025-09-09T11:18:00-04:00'::timestamptz, '2025-09-09T11:25:00-04:00'::timestamptz, 'NY', 420, '7m', 'Trend Continuation', 'Clean setup. Followed the plan.', '1m', -0.97, 2, 'Overconfident', 'Hesitant', 3, true, 'Ranging', false, 'Ignored plan', 'Day trade', 'Waited for the pullback instead of chasing.', null, 'app_review_seed:v1:trade:064'),
('31240e42-a1a6-5dca-b698-ea2f811933e0'::uuid, 65, '2025-09-09'::date, 'MNQ', 'Long', 2, 23024.5, 23049.5, 25.0, 97.96, '2025-09-09T12:08:00-04:00'::timestamptz, '2025-09-09T12:24:00-04:00'::timestamptz, 'NY', 960, '16m', 'Failed Breakout', 'Overtraded after giving back the morning profit.', '2m', 1.27, 2, 'Focused', 'Calm', 3, true, 'Choppy', false, null, 'Swing scalp', 'Stayed patient after the first loss.', null, 'app_review_seed:v1:trade:065'),
('034c0f6d-68de-5245-ac53-080ad550cb8e'::uuid, 66, '2025-09-10'::date, 'MNQ', 'Long', 3, 23035.8, 23050.8, 15.0, 87.96, '2025-09-10T14:05:00-04:00'::timestamptz, '2025-09-10T14:16:00-04:00'::timestamptz, 'NY', 660, '11m', 'Opening Range Breakout', 'Entered before confirmation.', '5m', 2.45, 5, 'Fearful', 'Focused', 3, true, 'High Volume', false, null, 'Scalp', 'Entered before confirmation.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:066'),
('6e3f0335-19f4-508c-abaa-d946b71a8117'::uuid, 67, '2025-09-10'::date, 'MNQ', 'Long', 2, 23047.1, 23062.1, 15.0, 57.96, '2025-09-10T14:48:00-04:00'::timestamptz, '2025-09-10T14:55:00-04:00'::timestamptz, 'NY', 420, '7m', 'VWAP Reclaim', 'Cut it when the setup invalidated.', '15m', 1.82, 5, 'FOMO', 'Focused', 5, true, 'Volatile', false, null, 'Day trade', 'Revenge click after the stop — noted for review.', null, 'app_review_seed:v1:trade:067'),
('803d5a2a-2728-5404-ae0d-80deb90ad60f'::uuid, 68, '2025-09-10'::date, 'NQ', 'Short', 1, 23073.4, 23063.4, 10.0, 195.96, '2025-09-10T15:25:00-04:00'::timestamptz, '2025-09-10T15:56:00-04:00'::timestamptz, 'NY', 1860, '31m', 'Pullback to 9 EMA', 'Good trade, execution could have been better.', '1m', 2.71, 5, 'Frustrated', 'Focused', 5, true, 'Strong Trend', false, null, 'Swing scalp', 'Waited for the pullback instead of chasing.', null, 'app_review_seed:v1:trade:068'),
('f9ef7202-4be3-58da-943f-56374e7fa0b9'::uuid, 69, '2025-09-11'::date, 'MNQ', 'Long', 2, 23069.7, 23094.7, 25.0, 97.96, '2025-09-11T09:35:00-04:00'::timestamptz, '2025-09-11T10:50:00-04:00'::timestamptz, 'NY', 4500, '1h 15m', 'Supply/Demand Fade', 'Revenge click after the stop — noted for review.', '2m', 1.8, 3, 'Hesitant', 'Calm', 5, true, 'Low Volume', false, null, 'Scalp', 'Stayed patient after the first loss.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:069'),
('ae569d74-cc3b-5d8d-9274-4ede73b2783d'::uuid, 70, '2025-09-11'::date, 'MNQ', 'Short', 2, 23096.0, 23108.0, -12.0, -50.04, '2025-09-11T10:05:00-04:00'::timestamptz, '2025-09-11T10:27:00-04:00'::timestamptz, 'NY', 1320, '22m', 'Trend Continuation', 'Partial at VWAP, runner stopped at BE.', '5m', -1.15, 3, 'Overconfident', 'Fearful', 3, false, 'Trending', false, 'Early entry', 'Day trade', 'Entered before confirmation.', 'VWAP, prior day high', 'app_review_seed:v1:trade:070'),
('18552c10-ad96-589c-bf68-70c0a406e07f'::uuid, 71, '2025-09-11'::date, 'MNQ', 'Long', 2, 23092.3, 23107.3, 15.0, 57.96, '2025-09-11T10:42:00-04:00'::timestamptz, '2025-09-11T11:04:00-04:00'::timestamptz, 'NY', 1320, '22m', 'Failed Breakout', 'Skipped first signal, took the second — worked out.', '15m', 1.79, 4, 'Confident', 'Calm', 3, true, 'Ranging', false, null, 'Swing scalp', 'Revenge click after the stop — noted for review.', null, 'app_review_seed:v1:trade:071'),
('b3a04396-5a0d-58e9-b90a-3662768ab9e3'::uuid, 72, '2025-09-11'::date, 'NQ', 'Long', 1, 23103.6, 23109.6, 6.0, 115.96, '2025-09-11T11:18:00-04:00'::timestamptz, '2025-09-11T11:49:00-04:00'::timestamptz, 'NY', 1860, '31m', 'Opening Range Breakout', 'Waited for the pullback instead of chasing.', '1m', 2.61, 2, 'Calm', 'Confident', 3, true, 'Choppy', false, null, 'Scalp', 'Waited for the pullback instead of chasing.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:072'),
('c40ba154-447a-57f3-9f13-b5dae6995151'::uuid, 73, '2025-09-11'::date, 'MNQ', 'Short', 2, 23129.9, 23129.65, 0.25, -1.04, '2025-09-11T12:08:00-04:00'::timestamptz, '2025-09-11T12:24:00-04:00'::timestamptz, 'NY', 960, '16m', 'VWAP Reclaim', 'Good entry but took profit too early.', '2m', 0.25, 5, 'Calm', 'Calm', 3, true, 'High Volume', false, null, 'Day trade', 'Stayed patient after the first loss.', null, 'app_review_seed:v1:trade:073'),
('c750f267-a4dd-563f-81ee-bf27344b2d72'::uuid, 74, '2025-09-12'::date, 'MNQ', 'Long', 2, 23126.2, 23138.2, 12.0, 45.96, '2025-09-12T14:05:00-04:00'::timestamptz, '2025-09-12T14:21:00-04:00'::timestamptz, 'NY', 960, '16m', 'Pullback to 9 EMA', 'Chased the second entry. Should have left it alone.', '5m', 1.12, 5, 'Fearful', 'Focused', 4, true, 'Volatile', false, null, 'Swing scalp', 'Entered before confirmation.', null, 'app_review_seed:v1:trade:074'),
('4c2417e6-6df0-5c90-8943-9448cd45d5e8'::uuid, 75, '2025-09-12'::date, 'MNQ', 'Short', 2, 22872.5, 22842.5, 30.0, 117.96, '2025-09-12T14:48:00-04:00'::timestamptz, '2025-09-12T15:32:00-04:00'::timestamptz, 'NY', 2640, '44m', 'Supply/Demand Fade', 'Stayed patient after the first loss.', '15m', 1.11, 5, 'FOMO', 'Focused', 4, true, 'Strong Trend', false, null, 'Scalp', 'Revenge click after the stop — noted for review.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:075'),
('876ae051-537d-58cb-8561-ab21b94d4426'::uuid, 76, '2025-09-14'::date, 'NQ', 'Short', 1, 22883.8, 22871.8, 12.0, 235.96, '2025-09-14T09:35:00-04:00'::timestamptz, '2025-09-14T09:39:00-04:00'::timestamptz, 'NY', 240, '4m', 'Trend Continuation', 'Clean setup. Followed the plan.', '1m', 2.54, 5, 'Frustrated', 'Confident', 4, true, 'Low Volume', false, null, 'Day trade', 'Waited for the pullback instead of chasing.', null, 'app_review_seed:v1:trade:076'),
('96df53a1-473f-525c-b868-2e9c3b034d83'::uuid, 77, '2025-09-15'::date, 'MNQ', 'Long', 3, 22880.1, 22900.1, 20.0, 117.96, '2025-09-15T10:42:00-04:00'::timestamptz, '2025-09-15T11:04:00-04:00'::timestamptz, 'NY', 1320, '22m', 'Failed Breakout', 'Overtraded after giving back the morning profit.', '2m', 2.36, 5, 'Hesitant', 'Focused', 5, true, 'Trending', false, null, 'Swing scalp', 'Stayed patient after the first loss.', 'VWAP, prior day high', 'app_review_seed:v1:trade:077'),
('b71165ef-b5b8-5382-89e8-5208279bddc4'::uuid, 78, '2025-09-15'::date, 'MNQ', 'Short', 2, 22906.4, 22922.4, -16.0, -66.04, '2025-09-15T11:18:00-04:00'::timestamptz, '2025-09-15T12:33:00-04:00'::timestamptz, 'NY', 4500, '1h 15m', 'Opening Range Breakout', 'Entered before confirmation.', '5m', -1.18, 2, 'Fearful', 'Hesitant', 1, true, 'Ranging', false, 'Revenge trade', 'Scalp', 'Entered before confirmation.', 'Opening drive, liquidity sweep', 'app_review_seed:v1:trade:078')
) AS v(
  id uuid, seq int, trade_date date, ticker text, direction text, contracts int,
  entry_price numeric, exit_price numeric, points numeric, pnl numeric,
  entry_time timestamptz, exit_time timestamptz, session text, duration_seconds int,
  duration_text text, strategy text, notes text, timeframe text, rr numeric,
  confidence int, emotion text, exit_emotion text, execution_rating int,
  followed_plan boolean, market_condition text, news_event boolean,
  mistake_type text, trade_type text, psychology_notes text, top_confluences text,
  import_fingerprint text
);

CREATE TEMP TABLE _app_review_seed_checkins ON COMMIT DROP AS
SELECT * FROM (VALUES

('d2cc5c1c-3d25-536b-b80f-d2460df4bf6f'::uuid, '2025-07-29'::date, 7.5, 4, 4, 4, 4, 4, '[app_review_seed:v1] Felt dialed in pre-market. Kept size normal.', 'app_review_seed:v1:checkin:2025-07-29'),
('01aa51b6-7ad2-5eec-8569-9955555fde88'::uuid, '2025-07-30'::date, 7.5, 4, 4, 4, 4, 4, '[app_review_seed:v1] Felt dialed in pre-market. Kept size normal.', 'app_review_seed:v1:checkin:2025-07-30'),
('455ced6a-5128-5f20-a58a-0fa93110ca87'::uuid, '2025-07-31'::date, 7.0, 3, 3, 3, 3, 3, '[app_review_seed:v1] Standard morning routine. Coffee and levels marked.', 'app_review_seed:v1:checkin:2025-07-31'),
('348b5581-44e7-5963-bc9f-2f1c0cf547e9'::uuid, '2025-08-01'::date, 7.0, 3, 3, 3, 3, 3, '[app_review_seed:v1] Standard morning routine. Coffee and levels marked.', 'app_review_seed:v1:checkin:2025-08-01'),
('e295f799-8e4c-5c96-8e91-00ce96bdb9ff'::uuid, '2025-08-04'::date, 6.0, 3, 2, 2, 2, 2, '[app_review_seed:v1] Rough night sleep. Need to reset before tomorrow.', 'app_review_seed:v1:checkin:2025-08-04'),
('a66fc04d-a291-5bca-80d0-428d09213df4'::uuid, '2025-08-06'::date, 7.5, 4, 4, 4, 4, 4, '[app_review_seed:v1] Felt dialed in pre-market. Kept size normal.', 'app_review_seed:v1:checkin:2025-08-06'),
('4a3878bf-564b-5308-a5d0-d6fce376653b'::uuid, '2025-08-11'::date, 6.0, 3, 2, 2, 2, 2, '[app_review_seed:v1] Rough night sleep. Need to reset before tomorrow.', 'app_review_seed:v1:checkin:2025-08-11'),
('0db00d4a-8f18-5c62-a3cb-c357d434d7ba'::uuid, '2025-08-12'::date, 7.0, 3, 3, 3, 3, 3, '[app_review_seed:v1] Standard morning routine. Coffee and levels marked.', 'app_review_seed:v1:checkin:2025-08-12'),
('9df4fa29-c8e3-5681-bb80-bac30071c4cc'::uuid, '2025-08-13'::date, 7.0, 3, 3, 3, 3, 3, '[app_review_seed:v1] Standard morning routine. Coffee and levels marked.', 'app_review_seed:v1:checkin:2025-08-13'),
('a32d4eaa-0639-5b4d-ab40-ae8d790575f3'::uuid, '2025-08-14'::date, 6.0, 3, 2, 2, 2, 2, '[app_review_seed:v1] Rough night sleep. Need to reset before tomorrow.', 'app_review_seed:v1:checkin:2025-08-14'),
('1c44aeb2-40a9-5382-bb2c-adc40bd8aa7b'::uuid, '2025-08-17'::date, 7.0, 3, 3, 3, 3, 3, '[app_review_seed:v1] Standard morning routine. Coffee and levels marked.', 'app_review_seed:v1:checkin:2025-08-17'),
('222ce8cd-f955-5e0d-8957-e877ebb44a99'::uuid, '2025-08-18'::date, 7.5, 4, 4, 4, 4, 4, '[app_review_seed:v1] Felt dialed in pre-market. Kept size normal.', 'app_review_seed:v1:checkin:2025-08-18'),
('21bfd46d-9c76-5a5c-905f-b7d71f5ed416'::uuid, '2025-08-20'::date, 7.0, 3, 3, 3, 3, 3, '[app_review_seed:v1] Standard morning routine. Coffee and levels marked.', 'app_review_seed:v1:checkin:2025-08-20'),
('f1a3ca1a-9d65-5921-85fd-4e16108dc8c0'::uuid, '2025-08-25'::date, 7.5, 4, 4, 4, 4, 4, '[app_review_seed:v1] Felt dialed in pre-market. Kept size normal.', 'app_review_seed:v1:checkin:2025-08-25'),
('3bf15d9e-88df-5229-83f5-009be0907662'::uuid, '2025-08-26'::date, 7.0, 3, 3, 3, 3, 3, '[app_review_seed:v1] Standard morning routine. Coffee and levels marked.', 'app_review_seed:v1:checkin:2025-08-26'),
('97dcab86-6546-5b1a-8039-db14b50192ee'::uuid, '2025-08-29'::date, 7.0, 3, 3, 3, 3, 3, '[app_review_seed:v1] Standard morning routine. Coffee and levels marked.', 'app_review_seed:v1:checkin:2025-08-29'),
('ad31c774-7849-59a2-b8a0-92b399897870'::uuid, '2025-08-31'::date, 7.0, 3, 3, 3, 3, 3, '[app_review_seed:v1] Standard morning routine. Coffee and levels marked.', 'app_review_seed:v1:checkin:2025-08-31'),
('bc093174-00be-56a1-a0ac-cfd3dff22058'::uuid, '2025-09-01'::date, 7.0, 3, 3, 3, 3, 3, '[app_review_seed:v1] Standard morning routine. Coffee and levels marked.', 'app_review_seed:v1:checkin:2025-09-01'),
('da199f2e-f442-5e7a-8623-5c240a35e4e5'::uuid, '2025-09-02'::date, 6.0, 3, 2, 2, 2, 2, '[app_review_seed:v1] Rough night sleep. Need to reset before tomorrow.', 'app_review_seed:v1:checkin:2025-09-02'),
('46f28357-5632-5ce3-bb7b-92cb8cf10417'::uuid, '2025-09-03'::date, 7.0, 3, 3, 3, 3, 3, '[app_review_seed:v1] Standard morning routine. Coffee and levels marked.', 'app_review_seed:v1:checkin:2025-09-03'),
('85d86b65-d649-586a-a527-9f40101bb02f'::uuid, '2025-09-09'::date, 7.0, 3, 3, 3, 3, 3, '[app_review_seed:v1] Standard morning routine. Coffee and levels marked.', 'app_review_seed:v1:checkin:2025-09-09'),
('faf2bd74-c37e-54d0-aed1-3262512ed24c'::uuid, '2025-09-10'::date, 7.5, 4, 4, 4, 4, 4, '[app_review_seed:v1] Felt dialed in pre-market. Kept size normal.', 'app_review_seed:v1:checkin:2025-09-10'),
('4bc0b460-a310-5aa6-86c7-728969862850'::uuid, '2025-09-11'::date, 7.5, 4, 4, 4, 4, 4, '[app_review_seed:v1] Felt dialed in pre-market. Kept size normal.', 'app_review_seed:v1:checkin:2025-09-11'),
('82830a93-109a-524b-ad52-0c152b695a55'::uuid, '2025-09-12'::date, 7.5, 4, 4, 4, 4, 4, '[app_review_seed:v1] Felt dialed in pre-market. Kept size normal.', 'app_review_seed:v1:checkin:2025-09-12'),
('58e38f50-d025-5752-ac92-dca96973e43a'::uuid, '2025-09-15'::date, 7.0, 3, 3, 3, 3, 3, '[app_review_seed:v1] Standard morning routine. Coffee and levels marked.', 'app_review_seed:v1:checkin:2025-09-15')
) AS v(
  id uuid, check_in_date date, sleep_hours numeric, sleep_quality int, morning_rating int,
  stress_level int, energy_level int, focus_level int, notes text, seed_key text
);

DO $$
DECLARE
  target_user_id uuid := '00000000-0000-4000-8000-000000000001'::uuid;  -- REPLACE
  target_account_id uuid := '00000000-0000-4000-8000-000000000002'::uuid;  -- REPLACE
  acct_name text;
  acct_size text;
  acct_mode text;
  acct_category text;
  inserted_trades int;
  inserted_checkins int;
BEGIN
  IF target_user_id = '00000000-0000-4000-8000-000000000001'::uuid
     OR target_account_id = '00000000-0000-4000-8000-000000000002'::uuid THEN
    RAISE EXCEPTION 'Replace placeholder target_user_id and target_account_id UUIDs before running.';
  END IF;

  SELECT a.name, a.account_size, a.mode, a.category
    INTO acct_name, acct_size, acct_mode, acct_category
    FROM public.accounts a
   WHERE a.id = target_account_id AND a.user_id = target_user_id;

  IF acct_name IS NULL THEN
    RAISE EXCEPTION 'Account % does not belong to user % (or missing).', target_account_id, target_user_id;
  END IF;

  INSERT INTO public.trades (
    id, user_id, account_id, account_name, account_size, account_type, account_category,
    ticker, direction, mode, contracts, entry_price, exit_price, entry_time, exit_time,
    trade_date, pnl, rr, points, session, strategy, notes, timeframe, news_event,
    confidence, emotion, followed_plan, market_condition, psychology_notes,
    exit_emotion, execution_rating, duration_seconds, duration_text,
    is_public, public_description, image_display_mode, reviewed, is_initial_import,
    import_source, import_fingerprint, created_at, date,
    mistake_type, trade_type, top_confluences
  )
  SELECT
    s.id, target_user_id, target_account_id, acct_name, acct_size, acct_mode, acct_category,
    s.ticker, s.direction, acct_mode, s.contracts, s.entry_price, s.exit_price,
    s.entry_time, s.exit_time, s.trade_date, s.pnl, s.rr, s.points, s.session,
    s.strategy, s.notes, s.timeframe, s.news_event, s.confidence, s.emotion,
    s.followed_plan, s.market_condition, s.psychology_notes, s.exit_emotion,
    s.execution_rating, s.duration_seconds, s.duration_text,
    false, '', 'fit', true, false, 'manual', s.import_fingerprint, s.entry_time, s.entry_time,
    s.mistake_type, s.trade_type, s.top_confluences
  FROM _app_review_seed_trades s
  WHERE NOT EXISTS (
    SELECT 1 FROM public.trades t
    WHERE t.user_id = target_user_id AND t.import_fingerprint = s.import_fingerprint
  );

  GET DIAGNOSTICS inserted_trades = ROW_COUNT;

  INSERT INTO public.trader_daily_check_ins (
    id, user_id, check_in_date, sleep_hours, sleep_quality, morning_rating,
    stress_level, energy_level, focus_level, notes
  )
  SELECT
    c.id, target_user_id, c.check_in_date, c.sleep_hours, c.sleep_quality, c.morning_rating,
    c.stress_level, c.energy_level, c.focus_level, c.notes
  FROM _app_review_seed_checkins c
  WHERE NOT EXISTS (
    SELECT 1 FROM public.trader_daily_check_ins x
    WHERE x.user_id = target_user_id AND x.check_in_date = c.check_in_date
  );

  GET DIAGNOSTICS inserted_checkins = ROW_COUNT;
  RAISE NOTICE 'Inserted % trades, % check-ins (existing fingerprints/dates skipped).', inserted_trades, inserted_checkins;
END $$;

COMMIT;

-- =============================================================================
-- OPTIONAL ROLLBACK (separate transaction; replace placeholders)
-- =============================================================================
-- BEGIN;
-- DELETE FROM public.trader_daily_check_ins
--  WHERE user_id = '00000000-0000-4000-8000-000000000001'::uuid
--    AND notes LIKE '[app_review_seed:v1]%';
-- DELETE FROM public.trades
--  WHERE user_id = '00000000-0000-4000-8000-000000000001'::uuid
--    AND account_id = '00000000-0000-4000-8000-000000000002'::uuid
--    AND import_fingerprint LIKE 'app_review_seed:v1:trade:%';
-- COMMIT;

