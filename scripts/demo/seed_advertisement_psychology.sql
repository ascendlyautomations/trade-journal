-- =============================================================================
-- DEMO / MARKETING DATA ONLY
-- REQUIRES EXPLICIT USER ID
-- DO NOT RUN AGAINST UNINTENDED USERS
-- =============================================================================
--
-- Seeds Daily Check-In rows and missing per-trade psychology for ONE
-- advertisement/demo profile so Psychology analytics have source data.
-- It does not insert trades and does not change schema or RLS.
--
-- Trade writes, only when tradetraxs.demo_apply_seed is true, touch these
-- columns and only when the current value is missing:
--   confidence, emotion, followed_plan, psychology_notes,
--   exit_emotion, execution_rating
-- P&L, prices, size, symbol, side, account, dates, fees, screenshots,
-- broker metadata, and copy-trading metadata are never updated.
--
-- HOW TO RUN
-- 1. Paste the profile UUID over PASTE_UID_HERE below.
-- 2. Leave tradetraxs.demo_apply_seed = false.
-- 3. Run this whole file in the Supabase SQL editor (postgres role).
--    Nothing is written. The check-in grid is the first result.
--    The trade-psychology grid is the last result.
-- 4. Review both grids. seed_action says what would change.
-- 5. Set tradetraxs.demo_apply_seed to true and run the file again.
--    Existing check-ins are left untouched.
--    Missing trading days in the plan are inserted.
--    Missing psychology fields on this user's trades are filled.
--    A value that is already stored is never replaced.
--    Running it again writes nothing new.
--
-- REPLACE MODE is not enabled. A commented block at the bottom shows how a
-- destructive rebuild would have to be written. Do not use it on a profile
-- that already has real check-ins you want to keep.
--
-- Stress scale (current app, after 20260928230000):
--   1 Calm, 2 Slightly Stressed, 3 Moderate, 4 Stressed, 5 Very Stressed
-- Other 1-5 ratings: higher is better (sleep quality, morning, energy, focus).
-- check_in_date matches trades.trade_date, else trades.date.
-- That is the Eastern journal date the psychology window RPC joins on.
-- It is not the 6:00pm futures calendar rollover.
--
-- Allowed trade psychology values (app catalogs, not guessed):
--   confidence: integer 1-5 (1 Bad .. 5 Good). Null or 0 counts as missing.
--   emotion / exit_emotion: Confident, Calm, Focused, Fearful, FOMO,
--     Overconfident, Hesitant, Frustrated. Blank counts as missing.
--   followed_plan: boolean. False is real data and is kept. Only null is missing.
--   execution_rating: smallint 1-5, higher is better discipline. Only null is missing.
--   psychology_notes: free text. Some trades stay null on purpose.
-- Emotion and exit emotion use TradeReviewCatalog.emotions, the same list as
-- the web trade form and the iOS post-trade reflection picker.
-- =============================================================================

-- >>> PASTE THE ADVERTISEMENT PROFILE UUID HERE. Leave the token until then.
SELECT set_config('tradetraxs.demo_target_user_id', 'PASTE_UID_HERE', false);

-- false = preview only. true = insert missing check-ins and fill missing
-- psychology fields for that user only.
SELECT set_config('tradetraxs.demo_apply_seed', 'false', false);

CREATE OR REPLACE FUNCTION pg_temp.demo_psych_u(p_user uuid, p_date date, p_salt text)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT (('x' || substr(md5(p_user::text || '|' || to_char(p_date, 'YYYY-MM-DD') || '|' || p_salt), 1, 12))::bit(48)::bigint);
$fn$;

CREATE OR REPLACE FUNCTION pg_temp.advertisement_psychology_plan(p_user_id uuid)
RETURNS TABLE (
  check_in_date date,
  daily_pnl numeric,
  trade_count integer,
  win_count integer,
  loss_count integer,
  day_result text,
  psychology_band text,
  sleep_hours numeric,
  sleep_quality smallint,
  morning_rating smallint,
  stress_level smallint,
  energy_level smallint,
  focus_level smallint,
  notes text,
  logged_at timestamptz,
  already_exists boolean,
  seed_action text
)
LANGUAGE plpgsql
STABLE
AS $fn$
#variable_conflict use_column
BEGIN
  RETURN QUERY
  WITH user_span AS (
    SELECT (3 + (pg_temp.demo_psych_u(p_user_id, DATE '2020-01-01', 'span') % 3))::int AS span
  ),
  day_stats AS (
    SELECT
      coalesce(t.trade_date, t.date) AS trade_day,
      coalesce(sum(t.pnl), 0)::numeric AS daily_pnl,
      count(*)::int AS trade_count,
      count(*) FILTER (WHERE t.pnl > 0)::int AS win_count,
      count(*) FILTER (WHERE t.pnl < 0)::int AS loss_count
    FROM public.trades t
    WHERE t.user_id = p_user_id
      AND coalesce(t.trade_date, t.date) IS NOT NULL
    GROUP BY 1
  ),
  recent_days AS (
    SELECT *
    FROM day_stats
    ORDER BY trade_day DESC
    LIMIT 90
  ),
  baselines AS (
    SELECT
      coalesce(avg(daily_pnl) FILTER (WHERE daily_pnl > 0), 0)::numeric AS avg_win,
      coalesce(avg(abs(daily_pnl)) FILTER (WHERE daily_pnl < 0), 0)::numeric AS avg_loss_abs
    FROM recent_days
  ),
  scored AS (
    SELECT
      d.trade_day,
      d.daily_pnl,
      d.trade_count,
      d.win_count,
      d.loss_count,
      b.avg_win,
      b.avg_loss_abs,
      pg_temp.demo_psych_u(p_user_id, d.trade_day, 'day') AS h_day,
      pg_temp.demo_psych_u(
        p_user_id,
        (d.trade_day - ((d.trade_day - DATE '2020-01-01') % s.span))::date,
        'block'
      ) AS h_block,
      pg_temp.demo_psych_u(p_user_id, d.trade_day, 'flip') AS h_flip,
      pg_temp.demo_psych_u(p_user_id, d.trade_day, 'sleep') AS h_sleep,
      pg_temp.demo_psych_u(p_user_id, d.trade_day, 'sq') AS h_sq,
      pg_temp.demo_psych_u(p_user_id, d.trade_day, 'morning') AS h_morning,
      pg_temp.demo_psych_u(p_user_id, d.trade_day, 'stress') AS h_stress,
      pg_temp.demo_psych_u(p_user_id, d.trade_day, 'energy') AS h_energy,
      pg_temp.demo_psych_u(p_user_id, d.trade_day, 'focus') AS h_focus,
      pg_temp.demo_psych_u(p_user_id, d.trade_day, 'note') AS h_note,
      pg_temp.demo_psych_u(p_user_id, d.trade_day, 'clock') AS h_clock
    FROM recent_days d
    CROSS JOIN baselines b
    CROSS JOIN user_span s
  ),
  banded AS (
    SELECT
      s.*,
      CASE
        WHEN s.daily_pnl > 0 AND s.daily_pnl >= greatest(s.avg_win, 0.01) THEN 'strong_profit'
        WHEN s.daily_pnl > 0 THEN 'profit'
        WHEN s.daily_pnl < 0 AND s.avg_loss_abs > 0 AND abs(s.daily_pnl) > (s.avg_loss_abs * 1.5) THEN 'large_loss'
        WHEN s.daily_pnl < 0 THEN 'small_loss'
        ELSE 'flat'
      END AS day_result,
      CASE
        WHEN (s.h_block % 100) < 74 THEN 'good'
        WHEN (s.h_block % 100) < 90 THEN 'neutral'
        ELSE 'bad'
      END AS block_band,
      CASE
        WHEN (s.h_day % 100) < 68 THEN 'good'
        WHEN (s.h_day % 100) < 88 THEN 'neutral'
        ELSE 'bad'
      END AS day_band
    FROM scored s
  ),
  picked AS (
    SELECT
      b.*,
      CASE
        WHEN ((b.h_day / 100) % 100) < 72 THEN b.block_band
        ELSE b.day_band
      END AS base_band
    FROM banded b
  ),
  adjusted AS (
    SELECT
      p.*,
      CASE
        WHEN p.day_result = 'strong_profit' AND p.base_band = 'bad' AND (p.h_flip % 100) < 70 THEN 'good'
        WHEN p.day_result = 'strong_profit' AND p.base_band = 'neutral' AND (p.h_flip % 100) < 40 THEN 'good'
        WHEN p.day_result = 'profit' AND p.base_band = 'bad' AND (p.h_flip % 100) < 45 THEN 'neutral'
        WHEN p.day_result = 'small_loss' AND p.base_band = 'good' AND (p.h_flip % 100) < 18 THEN 'neutral'
        WHEN p.day_result = 'large_loss' AND p.base_band = 'good' AND (p.h_flip % 100) < 60 THEN 'bad'
        WHEN p.day_result = 'large_loss' AND p.base_band = 'good' AND (p.h_flip % 100) < 85 THEN 'neutral'
        WHEN p.day_result = 'large_loss' AND p.base_band = 'neutral' AND (p.h_flip % 100) < 40 THEN 'bad'
        WHEN p.day_result = 'flat' AND p.base_band = 'good' AND (p.h_flip % 100) < 25 THEN 'neutral'
        ELSE p.base_band
      END AS psychology_band
    FROM picked p
  ),
  shaped AS (
    SELECT
      a.trade_day AS check_in_date,
      round(a.daily_pnl, 2) AS daily_pnl,
      a.trade_count,
      a.win_count,
      a.loss_count,
      a.day_result,
      a.psychology_band,
      CASE
        WHEN a.psychology_band = 'good' AND (a.h_sleep % 23) = 0 THEN 5.5
        WHEN a.psychology_band = 'bad' AND (a.h_sleep % 19) = 0 THEN 7.5
        WHEN a.psychology_band = 'good' THEN round((7.0 + ((a.h_sleep % 4) * 0.5))::numeric, 1)
        WHEN a.psychology_band = 'neutral' THEN round((6.0 + ((a.h_sleep % 4) * 0.5))::numeric, 1)
        ELSE round((4.5 + ((a.h_sleep % 5) * 0.5))::numeric, 1)
      END AS sleep_hours,
      CASE a.psychology_band
        WHEN 'good' THEN least(5, 4 + (a.h_sq % 2))::smallint
        WHEN 'neutral' THEN least(5, 3 + (a.h_sq % 2) - CASE WHEN (a.h_sq % 5) = 0 THEN 1 ELSE 0 END)::smallint
        ELSE least(5, greatest(1, 1 + (a.h_sq % 3)))::smallint
      END AS sleep_quality,
      CASE a.psychology_band
        WHEN 'good' THEN least(5, 4 + (a.h_morning % 2))::smallint
        WHEN 'neutral' THEN (2 + (a.h_morning % 3))::smallint
        ELSE (1 + (a.h_morning % 3))::smallint
      END AS morning_rating,
      CASE a.psychology_band
        WHEN 'good' THEN least(3, 1 + (a.h_stress % 2) + CASE WHEN (a.h_stress % 17) = 0 THEN 1 ELSE 0 END)::smallint
        WHEN 'neutral' THEN (2 + (a.h_stress % 3))::smallint
        ELSE (4 + (a.h_stress % 2))::smallint
      END AS stress_level,
      CASE a.psychology_band
        WHEN 'good' THEN least(5, 4 + (a.h_energy % 2))::smallint
        WHEN 'neutral' THEN (2 + (a.h_energy % 3))::smallint
        ELSE greatest(1, 2 + (a.h_energy % 2) - CASE WHEN (a.h_energy % 4) = 0 THEN 1 ELSE 0 END)::smallint
      END AS energy_level,
      CASE
        WHEN a.psychology_band = 'bad' AND (a.h_focus % 11) = 0 THEN 4::smallint
        WHEN a.psychology_band = 'good' THEN least(5, 4 + (a.h_focus % 2))::smallint
        WHEN a.psychology_band = 'neutral' THEN (2 + (a.h_focus % 3))::smallint
        ELSE (1 + (a.h_focus % 3))::smallint
      END AS focus_level,
      CASE
        WHEN (a.h_note % 5) = 0 THEN NULL
        WHEN a.psychology_band = 'good' THEN (
          ARRAY[
            'Felt patient today. Waited for my setup.',
            'Good execution, stopped after target.',
            'Was a little tired but stayed disciplined.',
            'Stayed calm after getting stopped out.',
            'Took the A setup and left the rest.',
            'Slow morning, didnt force anything.',
            'Followed the plan even when it chopped.',
            'One clean trade then I was done.',
            'Size was normal. No hero stuff.',
            'Let the winner work a bit.',
            'Skipped the open and it paid off.',
            'Felt confident but entered a little early.',
            'Good loss. Followed the plan.',
            'Walked away green and didnt give it back.',
            'News was messy so I waited.',
            'Pretty boring session, which is fine.'
          ]
        )[1 + (a.h_note % 16)]
        WHEN a.psychology_band = 'neutral' THEN (
          ARRAY[
            'Fine day. Not sharp, not sloppy.',
            'A bit distracted but I managed it.',
            'Took one trade I didnt love.',
            'Was in and out. Nothing special.',
            'Hesitated on the first one.',
            'Followed most of the plan.',
            'Sleep was ok, focus came and went.',
            'Small day. Didnt press it.',
            'Second trade was average.',
            'Felt rushed around lunch.',
            'Cut it short once I got unsure.',
            'Not my best reads, but I kept size down.'
          ]
        )[1 + (a.h_note % 12)]
        ELSE (
          ARRAY[
            'Forced the second trade.',
            'Got frustrated after the first loss.',
            'Overtraded after giving back profit.',
            'Need to stop trading after two bad setups.',
            'Chased it. Knew it when I clicked.',
            'Tilted for a few minutes.',
            'Too many trades. Should have stopped.',
            'Moved my stop. Dumb.',
            'Tried to make it back too fast.',
            'Was annoyed before I even started.',
            'Ignored the plan on the last one.',
            'Revenge size on the loser. Wont do that again.',
            'Sat in a trade I should have scratched.',
            'Head wasnt in it. Traded anyway.'
          ]
        )[1 + (a.h_note % 14)]
      END AS notes,
      (
        (a.trade_day::timestamp + time '07:15' + make_interval(mins => (a.h_clock % 50)::int))
        AT TIME ZONE 'America/New_York'
      ) AS logged_at
    FROM adjusted a
  )
  SELECT
    shaped.check_in_date,
    shaped.daily_pnl,
    shaped.trade_count,
    shaped.win_count,
    shaped.loss_count,
    shaped.day_result,
    shaped.psychology_band,
    shaped.sleep_hours,
    shaped.sleep_quality,
    shaped.morning_rating,
    shaped.stress_level,
    shaped.energy_level,
    shaped.focus_level,
    shaped.notes,
    shaped.logged_at,
    EXISTS (
      SELECT 1
      FROM public.trader_daily_check_ins existing
      WHERE existing.user_id = p_user_id
        AND existing.check_in_date = shaped.check_in_date
    ) AS already_exists,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM public.trader_daily_check_ins existing
        WHERE existing.user_id = p_user_id
          AND existing.check_in_date = shaped.check_in_date
      ) THEN 'preserve_existing'
      ELSE 'insert_if_applied'
    END AS seed_action
  FROM shaped
  ORDER BY shaped.check_in_date;
END;
$fn$;

-- Trade hash: user id + trade id + journal date + field salt. No random().
CREATE OR REPLACE FUNCTION pg_temp.demo_psych_trade_u(
  p_user uuid,
  p_trade uuid,
  p_date date,
  p_salt text
)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT (
    ('x' || substr(
      md5(p_user::text || '|' || p_trade::text || '|' || to_char(p_date, 'YYYY-MM-DD') || '|' || p_salt),
      1,
      12
    ))::bit(48)::bigint
  );
$fn$;

-- Proposed psychology for every dated trade owned by the user.
-- Days inside the check-in plan use that plan's psychology_band, which is
-- also what a newly inserted check-in is built from. Days outside the plan
-- use an existing check-in when one is already stored, otherwise a fallback
-- band from the same hash. Existing non-empty trade fields are kept.
CREATE OR REPLACE FUNCTION pg_temp.advertisement_trade_psychology_plan(p_user_id uuid)
RETURNS TABLE (
  trade_date date,
  trade_id uuid,
  symbol text,
  pnl numeric,
  trade_number integer,
  check_in_band text,
  confidence integer,
  emotion text,
  followed_plan boolean,
  exit_emotion text,
  execution_rating smallint,
  psychology_notes text,
  seed_action text,
  fields_to_fill text,
  preserved_fields text
)
LANGUAGE plpgsql
STABLE
AS $fn$
#variable_conflict use_column
BEGIN
  RETURN QUERY
  WITH ordered AS (
    SELECT
      t.id,
      t.ticker,
      t.pnl,
      coalesce(t.trade_date, t.date) AS trade_day,
      t.confidence AS cur_confidence,
      t.emotion AS cur_emotion,
      t.followed_plan AS cur_followed_plan,
      t.psychology_notes AS cur_notes,
      t.exit_emotion AS cur_exit_emotion,
      t.execution_rating AS cur_execution,
      row_number() OVER (
        PARTITION BY coalesce(t.trade_date, t.date)
        ORDER BY nullif(btrim(t.entry_time), '') NULLS LAST, t.created_at NULLS LAST, t.id
      )::int AS trade_number,
      count(*) OVER (
        PARTITION BY coalesce(t.trade_date, t.date)
      )::int AS trades_that_day,
      coalesce(
        count(*) FILTER (WHERE coalesce(t.pnl, 0) < 0) OVER (
          PARTITION BY coalesce(t.trade_date, t.date)
          ORDER BY nullif(btrim(t.entry_time), '') NULLS LAST, t.created_at NULLS LAST, t.id
          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ),
        0
      )::int AS prior_losses
    FROM public.trades t
    WHERE t.user_id = p_user_id
      AND coalesce(t.trade_date, t.date) IS NOT NULL
  ),
  banded AS (
    SELECT
      o.*,
      pg_temp.demo_psych_trade_u(p_user_id, o.id, o.trade_day, 'story') AS h_story,
      pg_temp.demo_psych_trade_u(p_user_id, o.id, o.trade_day, 'plan') AS h_plan,
      pg_temp.demo_psych_trade_u(p_user_id, o.id, o.trade_day, 'exec') AS h_exec,
      pg_temp.demo_psych_trade_u(p_user_id, o.id, o.trade_day, 'conf') AS h_conf,
      pg_temp.demo_psych_trade_u(p_user_id, o.id, o.trade_day, 'emotion') AS h_em,
      pg_temp.demo_psych_trade_u(p_user_id, o.id, o.trade_day, 'exit') AS h_exit,
      pg_temp.demo_psych_trade_u(p_user_id, o.id, o.trade_day, 'note') AS h_note,
      pg_temp.demo_psych_trade_u(p_user_id, o.id, o.trade_day, 'band') AS h_band,
      COALESCE(
        plan.psychology_band,
        CASE
          WHEN ci.stress_level IS NULL AND ci.focus_level IS NULL THEN NULL
          WHEN coalesce(ci.stress_level, 3) >= 4 OR coalesce(ci.focus_level, 3) <= 2 THEN 'bad'
          WHEN coalesce(ci.stress_level, 3) <= 2 AND coalesce(ci.focus_level, 3) >= 4 THEN 'good'
          ELSE 'neutral'
        END,
        CASE
          WHEN (pg_temp.demo_psych_trade_u(p_user_id, o.id, o.trade_day, 'band') % 100) < 55 THEN 'good'
          WHEN (pg_temp.demo_psych_trade_u(p_user_id, o.id, o.trade_day, 'band') % 100) < 82 THEN 'neutral'
          ELSE 'bad'
        END
      ) AS check_in_band
    FROM ordered o
    LEFT JOIN pg_temp.advertisement_psychology_plan(p_user_id) plan
      ON plan.check_in_date = o.trade_day
    LEFT JOIN public.trader_daily_check_ins ci
      ON ci.user_id = p_user_id
     AND ci.check_in_date = o.trade_day
     AND plan.check_in_date IS NULL
  ),
  storied AS (
    SELECT
      b.*,
      CASE
        WHEN coalesce(b.pnl, 0) < 0
          AND b.check_in_band <> 'bad'
          AND b.trade_number <= 3
          AND (b.h_story % 100) < 22
          THEN 'disciplined_loss'
        WHEN coalesce(b.pnl, 0) > 0
          AND (b.h_story % 100) < 9
          THEN 'lucky_winner'
        WHEN b.trade_number >= 3
          AND b.prior_losses >= 1
          AND (b.h_story % 100) < 78
          THEN 'late_tilt'
        WHEN b.trade_number >= 4
          AND b.check_in_band = 'bad'
          AND (b.h_story % 100) < 70
          THEN 'late_tilt'
        WHEN b.trade_number >= 2
          AND b.prior_losses = 0
          AND coalesce(b.pnl, 0) > 0
          AND b.check_in_band = 'good'
          AND (b.h_story % 100) >= 9
          AND (b.h_story % 100) < 18
          THEN 'overconfident'
        WHEN b.check_in_band = 'bad' THEN 'stressed'
        WHEN b.check_in_band = 'good' THEN 'calm'
        ELSE 'mixed'
      END AS story
    FROM banded b
  ),
  proposed AS (
    SELECT
      s.*,
      CASE
        WHEN s.story = 'disciplined_loss' THEN true
        WHEN s.story = 'lucky_winner' THEN false
        WHEN s.story = 'late_tilt' AND coalesce(s.pnl, 0) <= 0 THEN (s.h_plan % 100) >= 64
        WHEN s.story = 'late_tilt' THEN (s.h_plan % 100) >= 40
        WHEN s.story = 'overconfident' THEN (s.h_plan % 100) >= 55
        WHEN s.trade_number = 1 AND s.check_in_band <> 'bad' THEN (s.h_plan % 100) < 88
        WHEN coalesce(s.pnl, 0) > 0 AND s.check_in_band = 'good' THEN (s.h_plan % 100) < 94
        WHEN coalesce(s.pnl, 0) > 0 AND s.check_in_band = 'bad' THEN (s.h_plan % 100) < 78
        WHEN coalesce(s.pnl, 0) > 0 THEN (s.h_plan % 100) < 90
        WHEN coalesce(s.pnl, 0) < 0 AND s.check_in_band = 'bad' THEN (s.h_plan % 100) < 42
        WHEN coalesce(s.pnl, 0) < 0 THEN (s.h_plan % 100) < 64
        ELSE (s.h_plan % 100) < 78
      END AS new_followed,
      CASE
        WHEN (s.h_exec % 6) = 0 AND s.story NOT IN ('disciplined_loss', 'lucky_winner') THEN NULL
        WHEN s.story = 'disciplined_loss' THEN (4 + (s.h_exec % 2))::smallint
        WHEN s.story = 'lucky_winner' THEN (1 + (s.h_exec % 3))::smallint
        WHEN s.story = 'late_tilt' THEN (1 + (s.h_exec % 3))::smallint
        WHEN s.trade_number >= 3 AND s.prior_losses >= 1 THEN (1 + (s.h_exec % 3))::smallint
        WHEN s.trade_number >= 4 THEN (2 + (s.h_exec % 2))::smallint
        WHEN s.story = 'overconfident' THEN (2 + (s.h_exec % 3))::smallint
        WHEN coalesce(s.pnl, 0) > 0 AND s.check_in_band <> 'bad' THEN (3 + (s.h_exec % 3))::smallint
        WHEN coalesce(s.pnl, 0) > 0 THEN (2 + (s.h_exec % 3))::smallint
        WHEN coalesce(s.pnl, 0) < 0 AND s.check_in_band = 'bad' THEN (1 + (s.h_exec % 3))::smallint
        WHEN coalesce(s.pnl, 0) < 0 THEN (2 + (s.h_exec % 3))::smallint
        ELSE 3::smallint
      END AS new_execution,
      CASE s.story
        WHEN 'overconfident' THEN 5
        WHEN 'disciplined_loss' THEN 3 + (s.h_conf % 2)::int
        WHEN 'lucky_winner' THEN 2 + (s.h_conf % 4)::int
        WHEN 'late_tilt' THEN 1 + (s.h_conf % 3)::int
        WHEN 'calm' THEN 3 + (s.h_conf % 3)::int
        WHEN 'stressed' THEN 1 + (s.h_conf % 3)::int
        ELSE 2 + (s.h_conf % 3)::int
      END AS new_confidence,
      CASE s.story
        WHEN 'disciplined_loss' THEN (ARRAY['Calm', 'Focused', 'Confident'])[1 + (s.h_em % 3)::int]
        WHEN 'lucky_winner' THEN (ARRAY['FOMO', 'Overconfident', 'Frustrated'])[1 + (s.h_em % 3)::int]
        WHEN 'late_tilt' THEN (ARRAY['Frustrated', 'FOMO', 'Fearful', 'Hesitant'])[1 + (s.h_em % 4)::int]
        WHEN 'overconfident' THEN 'Overconfident'
        WHEN 'calm' THEN (ARRAY['Calm', 'Focused', 'Confident', 'Calm', 'Focused'])[1 + (s.h_em % 5)::int]
        WHEN 'stressed' THEN (ARRAY['Frustrated', 'Fearful', 'FOMO', 'Hesitant', 'Frustrated'])[1 + (s.h_em % 5)::int]
        ELSE (ARRAY['Hesitant', 'Calm', 'Focused', 'Confident'])[1 + (s.h_em % 4)::int]
      END AS new_emotion,
      CASE
        WHEN (s.h_exit % 5) = 0 AND s.story NOT IN ('disciplined_loss', 'lucky_winner', 'late_tilt') THEN NULL
        WHEN s.story = 'disciplined_loss' THEN (ARRAY['Calm', 'Focused'])[1 + (s.h_exit % 2)::int]
        WHEN s.story = 'lucky_winner' THEN (ARRAY['Overconfident', 'FOMO', 'Confident'])[1 + (s.h_exit % 3)::int]
        WHEN s.story = 'late_tilt' THEN (ARRAY['Frustrated', 'Fearful', 'FOMO'])[1 + (s.h_exit % 3)::int]
        WHEN s.story = 'stressed' THEN (ARRAY['Frustrated', 'Fearful', 'Hesitant'])[1 + (s.h_exit % 3)::int]
        WHEN s.story = 'overconfident' THEN (ARRAY['Overconfident', 'Confident', 'FOMO'])[1 + (s.h_exit % 3)::int]
        WHEN coalesce(s.pnl, 0) > 0 THEN (ARRAY['Confident', 'Calm', 'Focused'])[1 + (s.h_exit % 3)::int]
        WHEN coalesce(s.pnl, 0) < 0 THEN (ARRAY['Calm', 'Focused', 'Hesitant'])[1 + (s.h_exit % 3)::int]
        ELSE (ARRAY['Hesitant', 'Calm'])[1 + (s.h_exit % 2)::int]
      END AS new_exit_emotion,
      CASE
        WHEN (s.h_note % 5) < 2 AND s.story NOT IN ('disciplined_loss', 'lucky_winner', 'late_tilt') THEN NULL
        WHEN s.story = 'disciplined_loss' AND (s.h_note % 6) = 0 THEN NULL
        WHEN s.story = 'disciplined_loss' THEN (
          ARRAY[
            'Good setup, just didn''t work.',
            'Execution was good, outcome wasn''t.',
            'Followed the plan.',
            'Stayed patient after the stop.'
          ]
        )[1 + (s.h_note % 4)::int]
        WHEN s.story = 'lucky_winner' THEN (
          ARRAY[
            'Forced this one.',
            'Got too confident after the winner.',
            'Didn''t follow the plan and it still paid.',
            'Chased it. Got lucky.'
          ]
        )[1 + (s.h_note % 4)::int]
        WHEN s.story = 'late_tilt' THEN (
          ARRAY[
            'Chased after the first loss.',
            'Should''ve stopped after two trades.',
            'Got frustrated and clicked anyway.',
            'Too many trades. This one was forced.'
          ]
        )[1 + (s.h_note % 4)::int]
        WHEN s.story = 'overconfident' THEN (
          ARRAY[
            'Got too confident after the winner.',
            'Size felt easy after the first one.',
            'Should have been done.'
          ]
        )[1 + (s.h_note % 3)::int]
        WHEN s.story = 'calm' THEN (
          ARRAY[
            'Waited for my setup.',
            'Followed the plan.',
            'Stayed patient after the stop.',
            'Entered a little early.',
            'Good read. Took it.'
          ]
        )[1 + (s.h_note % 5)::int]
        WHEN s.story = 'stressed' THEN (
          ARRAY[
            'Forced this one.',
            'Head wasn''t right and I traded anyway.',
            'Should''ve waited.',
            'Entered a little early.'
          ]
        )[1 + (s.h_note % 4)::int]
        ELSE (
          ARRAY[
            'Entered a little early.',
            'Fine trade. Nothing special.',
            'Followed the plan.',
            'Hesitated, then took it.'
          ]
        )[1 + (s.h_note % 4)::int]
      END AS new_notes
    FROM storied s
  ),
  merged AS (
    SELECT
      p.*,
      CASE
        WHEN p.cur_confidence IS NULL OR p.cur_confidence = 0 THEN p.new_confidence
        ELSE p.cur_confidence
      END AS out_confidence,
      CASE
        WHEN p.cur_emotion IS NULL OR btrim(p.cur_emotion) = '' THEN p.new_emotion
        ELSE p.cur_emotion
      END AS out_emotion,
      CASE
        WHEN p.cur_followed_plan IS NULL THEN p.new_followed
        ELSE p.cur_followed_plan
      END AS out_followed,
      CASE
        WHEN p.cur_notes IS NOT NULL AND btrim(p.cur_notes) <> '' THEN p.cur_notes
        ELSE p.new_notes
      END AS out_notes,
      CASE
        WHEN p.cur_exit_emotion IS NULL OR btrim(p.cur_exit_emotion) = '' THEN p.new_exit_emotion
        ELSE p.cur_exit_emotion
      END AS out_exit_emotion,
      CASE
        WHEN p.cur_execution IS NULL THEN p.new_execution
        ELSE p.cur_execution
      END AS out_execution,
      concat_ws(
        ', ',
        CASE WHEN (p.cur_confidence IS NULL OR p.cur_confidence = 0) AND p.new_confidence IS NOT NULL THEN 'confidence' END,
        CASE WHEN (p.cur_emotion IS NULL OR btrim(p.cur_emotion) = '') AND p.new_emotion IS NOT NULL THEN 'emotion' END,
        CASE WHEN p.cur_followed_plan IS NULL THEN 'followed_plan' END,
        CASE WHEN (p.cur_notes IS NULL OR btrim(p.cur_notes) = '') AND p.new_notes IS NOT NULL THEN 'psychology_notes' END,
        CASE WHEN (p.cur_exit_emotion IS NULL OR btrim(p.cur_exit_emotion) = '') AND p.new_exit_emotion IS NOT NULL THEN 'exit_emotion' END,
        CASE WHEN p.cur_execution IS NULL AND p.new_execution IS NOT NULL THEN 'execution_rating' END
      ) AS fill_list,
      concat_ws(
        ', ',
        CASE WHEN p.cur_confidence IS NOT NULL AND p.cur_confidence <> 0 THEN 'confidence' END,
        CASE WHEN p.cur_emotion IS NOT NULL AND btrim(p.cur_emotion) <> '' THEN 'emotion' END,
        CASE WHEN p.cur_followed_plan IS NOT NULL THEN 'followed_plan' END,
        CASE WHEN p.cur_notes IS NOT NULL AND btrim(p.cur_notes) <> '' THEN 'psychology_notes' END,
        CASE WHEN p.cur_exit_emotion IS NOT NULL AND btrim(p.cur_exit_emotion) <> '' THEN 'exit_emotion' END,
        CASE WHEN p.cur_execution IS NOT NULL THEN 'execution_rating' END
      ) AS keep_list
    FROM proposed p
  )
  SELECT
    m.trade_day,
    m.id,
    m.ticker,
    m.pnl,
    m.trade_number,
    m.check_in_band,
    m.out_confidence,
    m.out_emotion,
    m.out_followed,
    m.out_exit_emotion,
    m.out_execution,
    m.out_notes,
    CASE WHEN m.fill_list <> '' THEN 'fill_missing' ELSE 'untouched' END,
    NULLIF(m.fill_list, ''),
    NULLIF(m.keep_list, '')
  FROM merged m
  ORDER BY m.trade_day, m.trade_number, m.id;
END;
$fn$;

DO $seed$
DECLARE
  raw_id text := current_setting('tradetraxs.demo_target_user_id', false);
  apply_seed text := lower(current_setting('tradetraxs.demo_apply_seed', false));
  target_user_id uuid;
  planned_count integer;
  insert_count integer := 0;
  trade_update_count integer := 0;
BEGIN
  IF raw_id IS NULL OR btrim(raw_id) = '' OR raw_id = 'PASTE_UID_HERE' THEN
    RAISE EXCEPTION
      'DEMO SEED STOPPED: replace PASTE_UID_HERE with the advertisement profile UUID. Nothing was inserted.';
  END IF;

  BEGIN
    target_user_id := raw_id::uuid;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RAISE EXCEPTION
        'DEMO SEED STOPPED: TARGET_USER_ID is not a UUID (%). Nothing was inserted.', raw_id;
  END;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = target_user_id) THEN
    RAISE EXCEPTION
      'DEMO SEED STOPPED: profile % does not exist. Nothing was inserted.', target_user_id;
  END IF;

  DROP TABLE IF EXISTS pg_temp.demo_psych_plan;
  CREATE TEMP TABLE demo_psych_plan ON COMMIT PRESERVE ROWS AS
  SELECT *
  FROM pg_temp.advertisement_psychology_plan(target_user_id);

  SELECT count(*) INTO planned_count FROM pg_temp.demo_psych_plan;

  IF planned_count = 0 THEN
    RAISE EXCEPTION
      'DEMO SEED STOPPED: no trades with trade_date or date for %. Nothing was written.', target_user_id;
  END IF;

  DROP TABLE IF EXISTS pg_temp.demo_trade_psych_plan;
  CREATE TEMP TABLE demo_trade_psych_plan ON COMMIT PRESERVE ROWS AS
  SELECT *
  FROM pg_temp.advertisement_trade_psychology_plan(target_user_id);

  IF apply_seed = 'true' THEN
    INSERT INTO public.trader_daily_check_ins (
      user_id,
      check_in_date,
      sleep_hours,
      sleep_quality,
      morning_rating,
      stress_level,
      energy_level,
      focus_level,
      notes,
      created_at,
      updated_at
    )
    SELECT
      target_user_id,
      plan.check_in_date,
      plan.sleep_hours,
      plan.sleep_quality,
      plan.morning_rating,
      plan.stress_level,
      plan.energy_level,
      plan.focus_level,
      plan.notes,
      plan.logged_at,
      plan.logged_at
    FROM pg_temp.demo_psych_plan plan
    WHERE plan.seed_action = 'insert_if_applied'
    ON CONFLICT (user_id, check_in_date) DO NOTHING;

    GET DIAGNOSTICS insert_count = ROW_COUNT;

    -- Only the six psychology columns. Only this user. Only rows with a
    -- missing field. Each CASE keeps a value that is already stored.
    UPDATE public.trades t
    SET
      confidence = CASE
        WHEN t.confidence IS NULL OR t.confidence = 0 THEN p.confidence
        ELSE t.confidence
      END,
      emotion = CASE
        WHEN t.emotion IS NULL OR btrim(t.emotion) = '' THEN p.emotion
        ELSE t.emotion
      END,
      followed_plan = CASE
        WHEN t.followed_plan IS NULL THEN p.followed_plan
        ELSE t.followed_plan
      END,
      psychology_notes = CASE
        WHEN t.psychology_notes IS NULL OR btrim(t.psychology_notes) = '' THEN p.psychology_notes
        ELSE t.psychology_notes
      END,
      exit_emotion = CASE
        WHEN t.exit_emotion IS NULL OR btrim(t.exit_emotion) = '' THEN p.exit_emotion
        ELSE t.exit_emotion
      END,
      execution_rating = CASE
        WHEN t.execution_rating IS NULL THEN p.execution_rating
        ELSE t.execution_rating
      END
    FROM pg_temp.demo_trade_psych_plan p
    WHERE t.id = p.trade_id
      AND t.user_id = target_user_id
      AND p.seed_action = 'fill_missing';

    GET DIAGNOSTICS trade_update_count = ROW_COUNT;
    RAISE NOTICE 'DEMO SEED inserted % check-ins and filled psychology on % trades for %. Existing values were preserved.',
      insert_count, trade_update_count, target_user_id;
  ELSE
    RAISE NOTICE 'DEMO SEED preview only for % (% planned days). Set tradetraxs.demo_apply_seed to true to insert missing check-ins and fill missing psychology fields.',
      target_user_id, planned_count;
  END IF;
END;
$seed$;

-- Check-in preview.
-- seed_action = preserve_existing means a real check-in is already there.
-- seed_action = insert_if_applied means a row will be inserted only when
-- tradetraxs.demo_apply_seed is true.
SELECT
  check_in_date AS date,
  daily_pnl,
  trade_count,
  win_count,
  loss_count,
  day_result,
  psychology_band,
  sleep_hours,
  sleep_quality,
  morning_rating,
  stress_level,
  energy_level,
  focus_level,
  notes,
  already_exists,
  seed_action
FROM pg_temp.demo_psych_plan
ORDER BY check_in_date;

-- Trade psychology preview. Last result, so the SQL editor shows this grid.
-- CONFIDENCE through PSYCHOLOGY NOTE are the values after a future apply:
-- an existing value stays, a missing value shows what would be written.
-- seed_action = fill_missing means at least one field would be written.
-- seed_action = untouched means nothing on that trade would change.
-- fields_to_fill lists the columns that are missing and would be written.
-- preserved_fields lists columns that already have data and stay as they are.
-- A blank psychology note, exit emotion, or execution rating with seed_action
-- untouched on that column is intentional. Not every trade gets every field.
SELECT
  trade_date AS date,
  trade_id,
  symbol,
  pnl,
  trade_number AS trade_number_that_day,
  check_in_band,
  confidence,
  emotion,
  followed_plan,
  exit_emotion,
  execution_rating,
  psychology_notes AS psychology_note,
  seed_action,
  fields_to_fill,
  preserved_fields
FROM pg_temp.demo_trade_psych_plan
ORDER BY trade_date, trade_number_that_day, trade_id;

-- =============================================================================
-- POST-SEED VALIDATION
-- Run after apply_seed = true, in the same SQL editor session, or paste the
-- same UUID into the setting again. These statements do not write.
-- =============================================================================
--
-- SELECT set_config('tradetraxs.demo_target_user_id', 'PASTE_UID_HERE', false);
--
-- Total and range
-- SELECT count(*) AS check_ins,
--        min(check_in_date) AS first_date,
--        max(check_in_date) AS last_date
-- FROM public.trader_daily_check_ins
-- WHERE user_id = current_setting('tradetraxs.demo_target_user_id')::uuid;
--
-- Stress / focus / sleep quality distribution
-- SELECT stress_level, count(*) AS days
-- FROM public.trader_daily_check_ins
-- WHERE user_id = current_setting('tradetraxs.demo_target_user_id')::uuid
-- GROUP BY stress_level
-- ORDER BY stress_level;
--
-- SELECT focus_level, count(*) AS days
-- FROM public.trader_daily_check_ins
-- WHERE user_id = current_setting('tradetraxs.demo_target_user_id')::uuid
-- GROUP BY focus_level
-- ORDER BY focus_level;
--
-- SELECT sleep_quality, count(*) AS days
-- FROM public.trader_daily_check_ins
-- WHERE user_id = current_setting('tradetraxs.demo_target_user_id')::uuid
-- GROUP BY sleep_quality
-- ORDER BY sleep_quality;
--
-- Check-ins matched to trading days, plus profitable vs losing averages.
-- Stress 1 is calm. Stress 5 is very stressed.
-- SELECT
--   count(*) FILTER (WHERE ci.check_in_date IS NOT NULL) AS matched_days,
--   round(avg(ci.stress_level) FILTER (WHERE d.daily_pnl > 0), 2) AS avg_stress_on_profit_days,
--   round(avg(ci.stress_level) FILTER (WHERE d.daily_pnl < 0), 2) AS avg_stress_on_loss_days,
--   round(avg(ci.focus_level) FILTER (WHERE d.daily_pnl > 0), 2) AS avg_focus_on_profit_days,
--   round(avg(ci.focus_level) FILTER (WHERE d.daily_pnl < 0), 2) AS avg_focus_on_loss_days,
--   round(avg(ci.sleep_quality) FILTER (WHERE d.daily_pnl > 0), 2) AS avg_sleep_quality_on_profit_days,
--   round(avg(ci.sleep_quality) FILTER (WHERE d.daily_pnl < 0), 2) AS avg_sleep_quality_on_loss_days
-- FROM (
--   SELECT coalesce(t.trade_date, t.date) AS trade_day,
--          coalesce(sum(t.pnl), 0) AS daily_pnl
--   FROM public.trades t
--   WHERE t.user_id = current_setting('tradetraxs.demo_target_user_id')::uuid
--     AND coalesce(t.trade_date, t.date) IS NOT NULL
--   GROUP BY 1
-- ) d
-- LEFT JOIN public.trader_daily_check_ins ci
--   ON ci.user_id = current_setting('tradetraxs.demo_target_user_id')::uuid
--  AND ci.check_in_date = d.trade_day;
--
-- Duplicate dates (must be zero)
-- SELECT check_in_date, count(*)
-- FROM public.trader_daily_check_ins
-- WHERE user_id = current_setting('tradetraxs.demo_target_user_id')::uuid
-- GROUP BY check_in_date
-- HAVING count(*) > 1;
--
-- Orphan user (must be zero)
-- SELECT count(*) AS orphan_check_ins
-- FROM public.trader_daily_check_ins ci
-- LEFT JOIN public.profiles p ON p.id = ci.user_id
-- WHERE ci.user_id = current_setting('tradetraxs.demo_target_user_id')::uuid
--   AND p.id IS NULL;
--
-- Followed-plan rate and expectancy (average P&L).
-- SELECT
--   count(*) FILTER (WHERE followed_plan) AS followed_trades,
--   count(*) FILTER (WHERE followed_plan = false) AS not_followed_trades,
--   round(100.0 * count(*) FILTER (WHERE followed_plan) / nullif(count(*) FILTER (WHERE followed_plan IS NOT NULL), 0), 1) AS followed_pct,
--   round(avg(pnl) FILTER (WHERE followed_plan), 2) AS followed_expectancy,
--   round(avg(pnl) FILTER (WHERE followed_plan = false), 2) AS not_followed_expectancy
-- FROM public.trades
-- WHERE user_id = current_setting('tradetraxs.demo_target_user_id')::uuid;
--
-- SELECT confidence, count(*) AS trades
-- FROM public.trades
-- WHERE user_id = current_setting('tradetraxs.demo_target_user_id')::uuid
-- GROUP BY confidence
-- ORDER BY confidence;
--
-- SELECT execution_rating, count(*) AS trades
-- FROM public.trades
-- WHERE user_id = current_setting('tradetraxs.demo_target_user_id')::uuid
-- GROUP BY execution_rating
-- ORDER BY execution_rating;
--
-- SELECT emotion, count(*) AS trades
-- FROM public.trades
-- WHERE user_id = current_setting('tradetraxs.demo_target_user_id')::uuid
-- GROUP BY emotion
-- ORDER BY trades DESC;
--
-- SELECT exit_emotion, count(*) AS trades
-- FROM public.trades
-- WHERE user_id = current_setting('tradetraxs.demo_target_user_id')::uuid
-- GROUP BY exit_emotion
-- ORDER BY trades DESC;
--
-- Winning vs losing trade psychology.
-- SELECT
--   CASE WHEN pnl > 0 THEN 'win' WHEN pnl < 0 THEN 'loss' ELSE 'flat' END AS result,
--   count(*) AS trades,
--   round(100.0 * count(*) FILTER (WHERE followed_plan) / nullif(count(*), 0), 1) AS followed_pct,
--   round(avg(confidence), 2) AS avg_confidence,
--   round(avg(execution_rating), 2) AS avg_execution
-- FROM public.trades
-- WHERE user_id = current_setting('tradetraxs.demo_target_user_id')::uuid
-- GROUP BY 1
-- ORDER BY 1;
--
-- How full each psychology field is.
-- SELECT
--   count(*) AS trades,
--   round(100.0 * count(confidence) / nullif(count(*), 0), 1) AS confidence_pct,
--   round(100.0 * count(nullif(btrim(emotion), '')) / nullif(count(*), 0), 1) AS emotion_pct,
--   round(100.0 * count(followed_plan) / nullif(count(*), 0), 1) AS followed_plan_pct,
--   round(100.0 * count(nullif(btrim(psychology_notes), '')) / nullif(count(*), 0), 1) AS notes_pct,
--   round(100.0 * count(nullif(btrim(exit_emotion), '')) / nullif(count(*), 0), 1) AS exit_emotion_pct,
--   round(100.0 * count(execution_rating) / nullif(count(*), 0), 1) AS execution_pct
-- FROM public.trades
-- WHERE user_id = current_setting('tradetraxs.demo_target_user_id')::uuid;
--
-- After a preview run, this is how many trades would change and how many
-- check-ins would be inserted. After apply, fill_missing and insert_if_applied
-- should both be zero on the next preview.
-- SELECT
--   count(*) FILTER (WHERE seed_action = 'fill_missing') AS trades_that_would_change,
--   count(*) FILTER (WHERE seed_action = 'untouched') AS trades_untouched
-- FROM pg_temp.demo_trade_psych_plan;
--
-- SELECT
--   count(*) FILTER (WHERE seed_action = 'insert_if_applied') AS check_ins_that_would_insert,
--   count(*) FILTER (WHERE seed_action = 'preserve_existing') AS check_ins_preserved
-- FROM pg_temp.demo_psych_plan;
--
-- Emotions outside the app catalog (must be zero).
-- SELECT emotion, exit_emotion, count(*)
-- FROM public.trades
-- WHERE user_id = current_setting('tradetraxs.demo_target_user_id')::uuid
--   AND (
--     (emotion IS NOT NULL AND btrim(emotion) <> '' AND emotion NOT IN (
--       'Confident', 'Calm', 'Focused', 'Fearful', 'FOMO', 'Overconfident', 'Hesitant', 'Frustrated'
--     ))
--     OR (exit_emotion IS NOT NULL AND btrim(exit_emotion) <> '' AND exit_emotion NOT IN (
--       'Confident', 'Calm', 'Focused', 'Fearful', 'FOMO', 'Overconfident', 'Hesitant', 'Frustrated'
--     ))
--     OR (confidence IS NOT NULL AND confidence <> 0 AND confidence NOT BETWEEN 1 AND 5)
--     OR (execution_rating IS NOT NULL AND execution_rating NOT BETWEEN 1 AND 5)
--   )
-- GROUP BY emotion, exit_emotion;
--
-- =============================================================================
-- REPLACE MODE (NOT ENABLED)
-- Default runs never delete. To rebuild demo check-ins you would have to
-- delete only this user's rows on the planned dates, then insert again.
-- That delete does not clear trade psychology fields.
-- Do not run this if those dates contain real check-ins you want to keep.
--
-- DELETE FROM public.trader_daily_check_ins ci
-- USING pg_temp.demo_psych_plan plan
-- WHERE ci.user_id = current_setting('tradetraxs.demo_target_user_id')::uuid
--   AND ci.check_in_date = plan.check_in_date;
-- =============================================================================
