-- =============================================================================
-- TradeTraxs — reusable test trading account seed (GENERATOR)
-- =============================================================================
-- Tuned for native iOS Performance Reports + Psychology Reports (deterministic
-- psychology analytics engine inputs). R:R fields follow TradePointsAndRealizedRr
-- / lib/tradePointsAndRealizedRr.ts: `rr` = targeted (positive), `points` =
-- points targeted (plan), `realized_rr` / `exit_rr` stored for manual trades.
--
-- Populates a dedicated `public.accounts` row (created on first `apply`),
-- `public.trades`, and `public.trader_daily_check_ins` for ONE target user.
-- Does NOT create payouts, balances, posts, or other users' data.
--
-- Schema-aligned with:
--   public.trades (incl. rr, max_rr_reached, realized_rr, full_tp, early_exit,
--                  exit_rr, dollar_risk, psychology columns)
--   public.trader_daily_check_ins (sleep, stress, energy, focus, morning_rating)
--
-- Run in Supabase SQL editor or psql as a privileged role (bypasses RLS).
-- Review configuration, run dry_run first, then apply.
--
-- ---------------------------------------------------------------------------
-- QUICK START
-- ---------------------------------------------------------------------------
-- 1) Adjust CONFIG if needed (user, seed_id, mode). No account UUID required.
-- 2) v_run_mode := 'dry_run' — preview trades/check-ins; no account or writes.
-- 3) v_run_mode := 'validate' — consistency checks on existing seed rows.
-- 4) v_run_mode := 'apply' — create/reuse tagged test account + insert data.
-- 5) v_run_mode := 'cleanup' — remove seed trades/check-ins + tagged test account.
--
-- Fingerprints: `import_fingerprint` = `<namespace>:trade:<date>:<seq>`
-- Check-in notes prefix: `[<namespace>]`
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- >>> CONFIG — edit these values before running <<<
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  -- Target profile (auth.users / profiles.id)
  v_user_id            uuid := '30548db7-aeba-4b03-b3fb-4d9a1734ad03'::uuid;

  -- Email guard (recommended on shared/staging DBs; set NULL to skip).
  v_expected_email     text := 'nicholasautomationllc@gmail.com';

  -- Dedicated test account (created on first apply; located by accounts.note tag)
  v_config_account_name     text := 'Reports Test Account';
  v_config_account_category text := 'Personal';
  v_config_account_mode     text := 'Sim';
  v_config_account_size     text := '50000';  -- $50,000 Sim size label

  -- Seed namespace (used for fingerprints, notes, cleanup). Keep stable per dataset.
  v_seed_id            text := 'local-dev-001';
  v_namespace          text := 'test_trading_seed:' || v_seed_id;

  -- PRNG: `setseed()` argument in [-1, 1]; same value => same dataset.
  v_random_seed        double precision := 0.424242;

  -- Volume & window (Eastern trade dates, Mon–Fri trading days only)
  -- Default: 300 trades + 100 check-ins across the last ~6 calendar months.
  v_trade_count        integer := 300;
  v_check_in_count     integer := 100;
  v_start_date         date := (current_date - interval '6 months')::date;
  v_end_date           date := current_date;

  -- Behavior: run mode
  --   dry_run  — generate into temp tables, preview, ROLLBACK implied by caller
  --   apply    — insert rows (idempotent on import_fingerprint)
  --   cleanup  — delete seed rows + tagged test account (when safe)
  --   validate — consistency queries on existing seeded rows (no writes)
  v_run_mode           text := 'dry_run';

  -- Generation tuning
  v_psych_coverage     numeric := 0.98;  -- psychology report charts need dense tags
  v_target_win_rate    numeric := 0.57;

  -- Working vars
  v_auth_email         text;
  v_acct_user          uuid;
  v_acct_name          text;
  v_acct_category      text;
  v_acct_mode          text;
  v_acct_size          text;

  v_trading_days       date[] := ARRAY[]::date[];
  v_day_count          integer;
  v_trades_per_day     integer;
  v_trade_seq          integer := 0;
  v_checkin_seq        integer := 0;
  v_day_index          integer;
  v_d                  date;
  v_i                  integer;
  v_j                  integer;

  v_ticker             text;
  v_direction          text;
  v_contracts          integer;
  v_point_value        numeric;
  v_fee_per_contract   numeric;
  v_tick               numeric := 0.25;
  v_price_base         numeric;
  v_entry_price        numeric;
  v_exit_price         numeric;
  v_stop_price         numeric;
  v_target_price       numeric;
  v_points_targeted    numeric;  -- trades.points (plan "points targeted", always > 0)
  v_actual_points      numeric;  -- from entry/exit prices (P&L + realized R:R math)
  v_gross_pnl          numeric;
  v_pnl                numeric;
  v_fees               numeric;
  v_risk_points        numeric;
  v_targeted_rr        numeric;  -- trades.rr (targeted R:R, always > 0)
  v_realized_rr        numeric;
  v_max_rr_reached     numeric;
  v_exit_rr            numeric;
  v_dollar_risk        numeric;
  v_full_tp            boolean;
  v_early_exit         boolean;

  v_entry_ts           timestamptz;
  v_exit_ts            timestamptz;
  v_session            text;
  v_duration_seconds   integer;
  v_duration_text      text;

  v_strategy           text;
  v_timeframe          text;
  v_session_name       text;
  v_market_condition   text;
  v_trade_type         text;
  v_confidence         integer;
  v_emotion            text;
  v_exit_emotion       text;
  v_execution_rating   integer;
  v_followed_plan      boolean;
  v_mistake_type       text;
  v_news_event         boolean;
  v_notes              text;
  v_psychology_notes   text;
  v_top_confluences    text;

  v_sleep_hours        numeric;
  v_sleep_quality      integer;
  v_morning_rating     integer;  -- proxy for pre-market mood (1–5)
  v_stress_level       integer;  -- 1 calm → 5 very stressed (post-20260928230000 semantics)
  v_energy_level       integer;
  v_focus_level        integer;
  v_checkin_notes      text;

  v_win_bias           numeric;
  v_is_win             boolean;
  v_is_loss            boolean;
  v_is_scratch         boolean;
  v_streak             integer := 0;
  v_revenge_today      boolean;
  v_day_pnl            numeric;
  v_consec_losses      integer := 0;

  v_trade_id           uuid;
  v_checkin_id         uuid;
  v_fingerprint        text;

  v_tickers            text[] := ARRAY['MNQ','MNQ','MNQ','NQ','ES','ES'];
  v_strategies         text[] := ARRAY[
    'Opening Range Breakout','Liquidity Sweep','VWAP Reclaim',
    'Trend Pullback','Support / Resistance','Breakout Retest'
  ];
  v_timeframes         text[] := ARRAY['1m','2m','5m','15m'];
  v_markets            text[] := ARRAY['Trending','Strong Trend','Ranging','Choppy','Low Volume','High Volume','Volatile'];
  v_trade_types        text[] := ARRAY['Scalp','Day trade','Swing scalp'];
  v_emotions           text[] := ARRAY['Confident','Calm','Focused','Fearful','FOMO','Overconfident','Hesitant','Frustrated'];
  v_exit_emotions      text[] := ARRAY['Calm','Confident','Focused','Fearful','FOMO','Frustrated','Hesitant','Overconfident'];
  v_mistakes           text[] := ARRAY['Early entry','Revenge trade','Moved stop','Chased entry','Ignored plan','Oversized','Overtrading','Exited early'];

  v_inserted_trades    integer := 0;
  v_inserted_checkins  integer := 0;
  v_preview_limit      integer := 8;

  v_win_count          integer;
  v_total_pnl          numeric;
  v_preview_rr         numeric;
  v_seed_trade_count   integer;
  v_checkin_day_idx    integer;
  v_emotion_slot       integer;
  v_confidence_slot    integer;
  v_exec_slot          integer;
  v_sleep_slot         integer;
  v_stress_slot        integer;
  v_days_with_trades   integer;
  v_prev_trade_date    date;
  v_effective_checkins integer;
  v_account_id         uuid;
  v_det_account_id     uuid;
  v_account_fingerprint text;
  v_account_note       text;
  v_deleted_accounts   integer := 0;
BEGIN
  IF v_run_mode NOT IN ('dry_run', 'apply', 'cleanup', 'validate') THEN
    RAISE EXCEPTION 'Invalid v_run_mode: %', v_run_mode;
  END IF;

  IF v_trade_count < 1 OR v_check_in_count < 0 THEN
    RAISE EXCEPTION 'v_trade_count must be >= 1 and v_check_in_count >= 0';
  END IF;

  IF v_end_date < v_start_date THEN
    RAISE EXCEPTION 'v_end_date must be >= v_start_date';
  END IF;

  -- Identity guards
  IF v_expected_email IS NOT NULL THEN
    SELECT u.email INTO v_auth_email FROM auth.users u WHERE u.id = v_user_id;
    IF v_auth_email IS NULL THEN
      RAISE EXCEPTION 'auth.users has no row for user %', v_user_id;
    END IF;
    IF lower(trim(v_auth_email)) <> lower(trim(v_expected_email)) THEN
      RAISE EXCEPTION 'Email mismatch: expected % got %', v_expected_email, v_auth_email;
    END IF;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = v_user_id) THEN
    RAISE EXCEPTION 'profiles.id missing for user %', v_user_id;
  END IF;

  v_account_fingerprint := v_namespace || ':account';
  v_det_account_id := (
    substr(md5(v_account_fingerprint), 1, 8)  || '-' ||
    substr(md5(v_account_fingerprint), 9, 4)  || '-' ||
    '4' || substr(md5(v_account_fingerprint), 13, 3) || '-' ||
    'c' || substr(md5(v_account_fingerprint), 17, 3) || '-' ||
    substr(md5(v_account_fingerprint), 21, 12)
  )::uuid;
  v_account_note := '[' || v_namespace || '] dedicated reports test account';

  SELECT a.id, a.user_id, a.name, a.category, a.mode, a.account_size
  INTO v_account_id, v_acct_user, v_acct_name, v_acct_category, v_acct_mode, v_acct_size
  FROM public.accounts a
  WHERE a.user_id = v_user_id
    AND coalesce(a.note, '') LIKE ('[' || v_namespace || ']%')
  ORDER BY a.created_at NULLS LAST, a.id
  LIMIT 1;

  IF v_account_id IS NULL THEN
    v_account_id := v_det_account_id;
    v_acct_user := v_user_id;
    v_acct_name := v_config_account_name;
    v_acct_category := v_config_account_category;
    v_acct_mode := v_config_account_mode;
    v_acct_size := v_config_account_size;
  ELSIF v_acct_user <> v_user_id THEN
    RAISE EXCEPTION 'Resolved seed account % belongs to %, not target user %', v_account_id, v_acct_user, v_user_id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.accounts a
    WHERE a.id = v_det_account_id
      AND a.user_id <> v_user_id
  ) THEN
    RAISE EXCEPTION 'Deterministic account id % is already owned by another user', v_det_account_id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.accounts a
    WHERE a.user_id = v_user_id
      AND coalesce(a.note, '') LIKE ('[' || v_namespace || ']%')
      AND a.id <> v_account_id
  ) THEN
    RAISE EXCEPTION
      'Multiple accounts tagged with %; consolidate to one tagged account before re-run',
      v_namespace;
  END IF;

  -- -------------------------------------------------------------------------
  -- CLEANUP (namespace-scoped only)
  -- -------------------------------------------------------------------------
  IF v_run_mode = 'cleanup' THEN
    DELETE FROM public.trader_daily_check_ins ci
    WHERE ci.user_id = v_user_id
      AND coalesce(ci.notes, '') LIKE ('[' || v_namespace || ']%');

    DELETE FROM public.trades t
    WHERE t.user_id = v_user_id
      AND t.import_fingerprint LIKE (v_namespace || ':%');

    DELETE FROM public.accounts a
    WHERE a.user_id = v_user_id
      AND coalesce(a.note, '') LIKE ('[' || v_namespace || ']%')
      AND NOT EXISTS (
        SELECT 1 FROM public.trades t WHERE t.account_id = a.id
      );

    GET DIAGNOSTICS v_deleted_accounts = ROW_COUNT;

    IF EXISTS (
      SELECT 1
      FROM public.accounts a
      WHERE a.user_id = v_user_id
        AND coalesce(a.note, '') LIKE ('[' || v_namespace || ']%')
    ) THEN
      RAISE WARNING '[%] tagged test account retained — delete or reassign remaining trades on that account first',
        v_namespace;
    END IF;

    RAISE NOTICE '[%] cleanup complete for user % (removed % tagged account(s) with no remaining trades)',
      v_namespace, v_user_id, v_deleted_accounts;
    RETURN;
  END IF;

  -- -------------------------------------------------------------------------
  -- VALIDATE (existing seeded rows)
  -- -------------------------------------------------------------------------
  IF v_run_mode = 'validate' THEN
    RAISE NOTICE '--- validate: % ---', v_namespace;
    RAISE NOTICE 'Seed account: % (name=%)', v_account_id, coalesce(v_acct_name, v_config_account_name);

    SELECT count(*) INTO v_seed_trade_count
    FROM public.trades t
    WHERE t.user_id = v_user_id
      AND t.account_id = v_account_id
      AND t.import_fingerprint LIKE (v_namespace || ':%');

    IF coalesce(v_seed_trade_count, 0) = 0 THEN
      RAISE NOTICE 'No seeded trades found for namespace %', v_namespace;
      RETURN;
    END IF;

    RAISE NOTICE 'Trade count: %', (
      SELECT count(*) FROM public.trades t
      WHERE t.user_id = v_user_id AND t.import_fingerprint LIKE (v_namespace || ':%')
    );

    RAISE NOTICE 'Check-in count: %', (
      SELECT count(*) FROM public.trader_daily_check_ins ci
      WHERE ci.user_id = v_user_id AND coalesce(ci.notes, '') LIKE ('[' || v_namespace || ']%')
    );

    RAISE NOTICE 'PnL math violations (price-derived points): %', (
      WITH x AS (
        SELECT
          t.id,
          t.ticker,
          t.contracts,
          t.pnl,
          t.direction,
          t.entry_price,
          t.exit_price,
          CASE t.ticker
            WHEN 'MNQ' THEN 2::numeric
            WHEN 'NQ'  THEN 20::numeric
            WHEN 'ES'  THEN 50::numeric
            ELSE NULL
          END AS pv,
          CASE t.ticker
            WHEN 'MNQ' THEN 1.02::numeric
            WHEN 'NQ'  THEN 4.04::numeric
            WHEN 'ES'  THEN 4.04::numeric
            ELSE NULL
          END AS fee
        FROM public.trades t
        WHERE t.user_id = v_user_id
          AND t.import_fingerprint LIKE (v_namespace || ':%')
      )
      SELECT count(*)
      FROM x
      WHERE abs(
        round((
          (CASE WHEN x.direction = 'Long' THEN x.exit_price - x.entry_price ELSE x.entry_price - x.exit_price END)
          * x.pv * x.contracts - x.fee * x.contracts
        )::numeric, 2)
        - round(coalesce(x.pnl, 0)::numeric, 2)
      ) > 0.08
    );

    RAISE NOTICE 'Realized R:R mismatches (excl. Full TP canonical stored R): %', (
      WITH x AS (
        SELECT
          t.full_tp,
          t.pnl,
          t.points AS points_targeted,
          t.rr AS targeted_rr,
          t.realized_rr,
          CASE WHEN t.direction = 'Long' THEN t.exit_price - t.entry_price ELSE t.entry_price - t.exit_price END AS actual_pts
        FROM public.trades t
        WHERE t.user_id = v_user_id
          AND t.import_fingerprint LIKE (v_namespace || ':%')
          AND t.points > 0 AND t.rr > 0 AND t.realized_rr IS NOT NULL
      )
      SELECT count(*)
      FROM x
      WHERE (
        coalesce(x.full_tp, false) = false
        OR x.pnl <= 0
      )
      AND abs(
        round((x.actual_pts * x.targeted_rr / x.points_targeted)::numeric, 2)
        - round(x.realized_rr::numeric, 2)
      ) > 0.08
    );

    RAISE NOTICE 'Full TP winners with realized_rr != targeted rr: %', (
      SELECT count(*)
      FROM public.trades t
      WHERE t.user_id = v_user_id
        AND t.import_fingerprint LIKE (v_namespace || ':%')
        AND t.full_tp IS TRUE
        AND coalesce(t.pnl, 0) > 0
        AND t.rr IS NOT NULL
        AND t.realized_rr IS NOT NULL
        AND abs(round(t.realized_rr::numeric, 2) - round(t.rr::numeric, 2)) > 0.02
    );

    RAISE NOTICE 'Disciplined vs impulsive avg PnL: %', (
      SELECT jsonb_build_object(
        'disciplined_avg', round(avg(t.pnl) FILTER (
          WHERE t.followed_plan IS true AND coalesce(t.execution_rating, 0) >= 4
        )::numeric, 2),
        'impulsive_avg', round(avg(t.pnl) FILTER (
          WHERE t.followed_plan IS false
             OR coalesce(t.execution_rating, 0) <= 2
             OR t.mistake_type IS NOT NULL
        )::numeric, 2)
      )
      FROM public.trades t
      WHERE t.user_id = v_user_id
        AND t.import_fingerprint LIKE (v_namespace || ':%')
    );

    RAISE NOTICE 'Poor sleep (quality<=2) avg PnL vs good sleep (quality>=4): %', (
      SELECT jsonb_build_object(
        'poor_sleep_day_pnl', round(avg(d.day_pnl) FILTER (WHERE d.sleep_quality <= 2)::numeric, 2),
        'good_sleep_day_pnl', round(avg(d.day_pnl) FILTER (WHERE d.sleep_quality >= 4)::numeric, 2)
      )
      FROM (
        SELECT
          ci.check_in_date,
          max(ci.sleep_quality) AS sleep_quality,
          sum(t.pnl) AS day_pnl
        FROM public.trader_daily_check_ins ci
        LEFT JOIN public.trades t
          ON t.user_id = ci.user_id
         AND t.trade_date = ci.check_in_date
         AND t.import_fingerprint LIKE (v_namespace || ':%')
        WHERE ci.user_id = v_user_id
          AND coalesce(ci.notes, '') LIKE ('[' || v_namespace || ']%')
        GROUP BY ci.check_in_date
      ) d
    );

    RETURN;
  END IF;

  -- -------------------------------------------------------------------------
  -- Ensure dedicated account exists (apply only; dry_run previews without writing)
  -- -------------------------------------------------------------------------
  IF v_run_mode = 'apply' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.accounts a
      WHERE a.user_id = v_user_id
        AND coalesce(a.note, '') LIKE ('[' || v_namespace || ']%')
    ) THEN
      INSERT INTO public.accounts (
        id, user_id, name, category, mode, account_size, can_add_trades, is_active,
        show_in_account_dropdowns, note
      ) VALUES (
        v_det_account_id, v_user_id, v_config_account_name, v_config_account_category,
        v_config_account_mode, v_config_account_size, true, true, true, v_account_note
      );

      v_account_id := v_det_account_id;
      v_acct_name := v_config_account_name;
      v_acct_category := v_config_account_category;
      v_acct_mode := v_config_account_mode;
      v_acct_size := v_config_account_size;

      RAISE NOTICE '[%] created dedicated test account % (%)',
        v_namespace, v_account_id, v_config_account_name;
    ELSE
      SELECT a.id, a.name, a.category, a.mode, a.account_size
      INTO v_account_id, v_acct_name, v_acct_category, v_acct_mode, v_acct_size
      FROM public.accounts a
      WHERE a.user_id = v_user_id
        AND coalesce(a.note, '') LIKE ('[' || v_namespace || ']%')
      ORDER BY a.created_at NULLS LAST, a.id
      LIMIT 1;

      RAISE NOTICE '[%] reusing dedicated test account % (%)',
        v_namespace, v_account_id, v_acct_name;
    END IF;
  END IF;

  -- -------------------------------------------------------------------------
  -- Temp staging
  -- -------------------------------------------------------------------------
  CREATE TEMP TABLE IF NOT EXISTS _tt_seed_trades (
    LIKE public.trades INCLUDING DEFAULTS
  ) ON COMMIT DROP;
  TRUNCATE _tt_seed_trades;

  CREATE TEMP TABLE IF NOT EXISTS _tt_seed_checkins (
    LIKE public.trader_daily_check_ins INCLUDING DEFAULTS
  ) ON COMMIT DROP;
  TRUNCATE _tt_seed_checkins;

  CREATE TEMP TABLE IF NOT EXISTS _tt_day_checkin (
    trade_date date PRIMARY KEY,
    sleep_hours numeric(4,1),
    sleep_quality smallint,
    morning_rating smallint,
    stress_level smallint,
    energy_level smallint,
    focus_level smallint,
    notes text
  ) ON COMMIT DROP;
  TRUNCATE _tt_day_checkin;

  CREATE TEMP TABLE IF NOT EXISTS _tt_day_trading_state (
    trade_date date PRIMARY KEY,
    day_pnl numeric,
    revenge_today boolean NOT NULL DEFAULT false
  ) ON COMMIT DROP;
  TRUNCATE _tt_day_trading_state;

  -- Build weekday list
  v_d := v_start_date;
  WHILE v_d <= v_end_date LOOP
    IF extract(isodow from v_d) < 6 THEN
      v_trading_days := array_append(v_trading_days, v_d);
    END IF;
    v_d := v_d + 1;
  END LOOP;

  v_day_count := coalesce(array_length(v_trading_days, 1), 0);
  IF v_day_count = 0 THEN
    RAISE EXCEPTION 'No weekdays between % and %', v_start_date, v_end_date;
  END IF;

  PERFORM setseed(v_random_seed);

  v_trades_per_day := greatest(1, ceil(v_trade_count::numeric / v_day_count)::integer);
  -- Round-robin assignment: every calendar day in range gets a trade once
  -- trade_count >= day_count; otherwise only the first trade_count days do.
  v_days_with_trades := CASE
    WHEN v_trade_count >= v_day_count THEN v_day_count
    ELSE v_trade_count
  END;

  IF v_check_in_count > v_days_with_trades THEN
    RAISE EXCEPTION
      'check_in_count (%) exceeds distinct trade days (%) for trade_count=% over % weekdays — widen the date range or lower check_ins',
      v_check_in_count, v_days_with_trades, v_trade_count, v_day_count;
  END IF;

  v_effective_checkins := v_check_in_count;

  -- Check-ins: evenly spread across days that will receive trades (never orphan dates).
  FOR v_i IN 1..v_effective_checkins LOOP
    IF v_effective_checkins <= 1 THEN
      v_checkin_day_idx := 1;
    ELSE
      v_checkin_day_idx := 1 + floor(
        ((v_i - 1)::numeric * (v_days_with_trades - 1)) / (v_effective_checkins - 1)
      )::integer;
    END IF;
    v_d := v_trading_days[v_checkin_day_idx];

    v_sleep_slot := ((v_i - 1) % 5) + 1;
    v_stress_slot := ((v_i + 1) % 5) + 1;
    v_sleep_quality := v_sleep_slot;
    v_stress_level := v_stress_slot;
    v_morning_rating := least(5, greatest(1, ((v_i + 2) % 5) + 1));

    v_sleep_hours := round((5.3 + v_sleep_quality * 0.55 + random() * 0.6)::numeric, 1);
    v_energy_level := least(5, greatest(1, v_sleep_quality + (CASE WHEN random() < 0.35 THEN -1 ELSE 0 END)));
    v_focus_level := least(5, greatest(1, v_energy_level + (CASE WHEN random() < 0.4 THEN -1 ELSE 0 END)));

    IF v_sleep_quality <= 2 THEN
      v_checkin_notes := format('[%s] Short night — keeping size smaller until focus improves.', v_namespace);
    ELSIF v_stress_level >= 4 THEN
      v_checkin_notes := format('[%s] Elevated stress; sticking to A+ setups only.', v_namespace);
    ELSE
      v_checkin_notes := format('[%s] Routine morning; coffee and checklist before the open.', v_namespace);
    END IF;

    INSERT INTO _tt_day_checkin (
      trade_date, sleep_hours, sleep_quality, morning_rating,
      stress_level, energy_level, focus_level, notes
    ) VALUES (
      v_d, v_sleep_hours, v_sleep_quality, v_morning_rating,
      v_stress_level, v_energy_level, v_focus_level, v_checkin_notes
    ) ON CONFLICT (trade_date) DO UPDATE SET
      sleep_hours = EXCLUDED.sleep_hours,
      sleep_quality = EXCLUDED.sleep_quality,
      morning_rating = EXCLUDED.morning_rating,
      stress_level = EXCLUDED.stress_level,
      energy_level = EXCLUDED.energy_level,
      focus_level = EXCLUDED.focus_level,
      notes = EXCLUDED.notes;
  END LOOP;

  -- -------------------------------------------------------------------------
  -- Trade generation (round-robin across weekdays — matches check-in dates)
  -- -------------------------------------------------------------------------
  v_prev_trade_date := NULL;

  WHILE v_trade_seq < v_trade_count LOOP
      v_day_index := (v_trade_seq % v_day_count) + 1;
      v_d := v_trading_days[v_day_index];

      IF v_prev_trade_date IS DISTINCT FROM v_d THEN
        SELECT dc.sleep_quality, dc.stress_level, dc.focus_level, dc.morning_rating
        INTO v_sleep_quality, v_stress_level, v_focus_level, v_morning_rating
        FROM _tt_day_checkin dc
        WHERE dc.trade_date = v_d;

        v_win_bias := v_target_win_rate;
        IF v_sleep_quality IS NOT NULL AND v_sleep_quality <= 2 THEN
          v_win_bias := v_win_bias - 0.12;
        ELSIF v_sleep_quality IS NOT NULL AND v_sleep_quality >= 4 THEN
          v_win_bias := v_win_bias + 0.06;
        END IF;
        IF v_stress_level IS NOT NULL AND v_stress_level >= 4 THEN
          v_win_bias := v_win_bias - 0.08;
        END IF;
        v_win_bias := greatest(0.38, least(0.72, v_win_bias));

        v_prev_trade_date := v_d;
      END IF;

      SELECT s.day_pnl, s.revenge_today
      INTO v_day_pnl, v_revenge_today
      FROM _tt_day_trading_state s
      WHERE s.trade_date = v_d;

      IF NOT FOUND THEN
        v_day_pnl := 0;
        v_revenge_today := false;
      END IF;

      v_trade_seq := v_trade_seq + 1;
      v_fingerprint := v_namespace || ':trade:' || to_char(v_d, 'YYYY-MM-DD') || ':' || lpad(v_trade_seq::text, 4, '0');

      v_trade_id := (
        substr(md5(v_fingerprint), 1, 8)  || '-' ||
        substr(md5(v_fingerprint), 9, 4)  || '-' ||
        '4' || substr(md5(v_fingerprint), 13, 3) || '-' ||
        'a' || substr(md5(v_fingerprint), 17, 3) || '-' ||
        substr(md5(v_fingerprint), 21, 12)
      )::uuid;

      v_ticker := v_tickers[1 + floor(random() * array_length(v_tickers, 1))::integer];
      v_direction := CASE WHEN random() < 0.52 THEN 'Long' ELSE 'Short' END;

      CASE v_ticker
        WHEN 'MNQ' THEN
          v_point_value := 2;
          v_fee_per_contract := 1.02;
          v_price_base := 22850 + (v_day_index * 2.5) + (random() - 0.5) * 40;
        WHEN 'NQ' THEN
          v_point_value := 20;
          v_fee_per_contract := 4.04;
          v_price_base := 22850 + (v_day_index * 2.5) + (random() - 0.5) * 40;
          v_contracts := 1;
        WHEN 'ES' THEN
          v_point_value := 50;
          v_fee_per_contract := 4.04;
          v_price_base := 5800 + (v_day_index * 0.35) + (random() - 0.5) * 12;
        ELSE
          v_point_value := 2;
          v_fee_per_contract := 1.02;
          v_price_base := 22850;
      END CASE;

      IF v_ticker <> 'NQ' THEN
        v_contracts := CASE
          WHEN random() < 0.35 THEN 1
          WHEN random() < 0.75 THEN 2
          ELSE 3
        END;
      END IF;

      v_strategy := v_strategies[1 + floor(random() * array_length(v_strategies, 1))::integer];
      v_timeframe := v_timeframes[1 + floor(random() * array_length(v_timeframes, 1))::integer];
      v_market_condition := v_markets[1 + floor(random() * array_length(v_markets, 1))::integer];
      v_trade_type := v_trade_types[1 + floor(random() * array_length(v_trade_types, 1))::integer];
      v_news_event := random() < 0.08;

      -- Session + timestamps (America/New_York)
      IF random() < 0.82 THEN
        v_session := 'NY';
        v_entry_ts := (v_d::timestamp + make_interval(hours => 9 + floor(random() * 7)::integer, mins => (ARRAY[5,12,18,22,35,42,48,55])[1 + floor(random() * 8)::integer])) AT TIME ZONE 'America/New_York';
      ELSIF random() < 0.92 THEN
        v_session := 'London';
        v_entry_ts := (v_d::timestamp + make_interval(hours => 3 + floor(random() * 5)::integer, mins => (ARRAY[5,12,18,22,35,42,48,55])[1 + floor(random() * 8)::integer])) AT TIME ZONE 'America/New_York';
      ELSE
        v_session := 'Asia';
        v_entry_ts := (v_d::timestamp + make_interval(hours => 18 + floor(random() * 3)::integer, mins => (ARRAY[5,12,18,22,35,42,48,55])[1 + floor(random() * 8)::integer])) AT TIME ZONE 'America/New_York';
      END IF;

      v_duration_seconds := greatest(120,
        CASE
          WHEN random() < 0.25 THEN 240 + floor(random() * 600)::integer
          WHEN random() < 0.65 THEN 900 + floor(random() * 1500)::integer
          ELSE 2400 + floor(random() * 2400)::integer
        END
      );
      v_exit_ts := v_entry_ts + make_interval(secs => v_duration_seconds);

      v_duration_text := CASE
        WHEN v_duration_seconds < 60 THEN v_duration_seconds::text || 's'
        WHEN v_duration_seconds < 3600 THEN (v_duration_seconds / 60)::integer::text || 'm'
        ELSE (v_duration_seconds / 3600)::integer::text || 'h ' || ((v_duration_seconds % 3600) / 60)::integer::text || 'm'
      END;

      v_is_scratch := random() < 0.035;
      v_is_win := NOT v_is_scratch AND random() < v_win_bias;
      v_is_loss := NOT v_is_scratch AND NOT v_is_win;

      -- Targeted plan (manual semantics — always stored positive)
      v_targeted_rr := round((0.9 + random() * 2.4)::numeric, 2);
      v_risk_points := round((3.5 + random() * 6.5)::numeric, 2);
      IF v_revenge_today OR (v_consec_losses >= 2 AND random() < 0.42) THEN
        v_risk_points := round(v_risk_points * 1.2, 2);
      END IF;

      v_points_targeted := round(v_risk_points * v_targeted_rr, 2);
      v_entry_price := round(v_price_base / v_tick) * v_tick;

      IF v_direction = 'Long' THEN
        v_stop_price := round((v_entry_price - v_risk_points) / v_tick) * v_tick;
        v_target_price := round((v_entry_price + v_points_targeted) / v_tick) * v_tick;
      ELSE
        v_stop_price := round((v_entry_price + v_risk_points) / v_tick) * v_tick;
        v_target_price := round((v_entry_price - v_points_targeted) / v_tick) * v_tick;
      END IF;

      v_full_tp := false;
      v_early_exit := false;
      v_exit_rr := NULL;

      IF v_is_win THEN
        IF random() < 0.38 THEN
          v_full_tp := true;
          v_exit_price := v_target_price;
        ELSIF random() < 0.62 THEN
          v_early_exit := true;
          v_exit_price := round((
            v_entry_price
            + (CASE WHEN v_direction = 'Long' THEN 1 ELSE -1 END)
            * v_risk_points * (0.45 + random() * 0.42)
          ) / v_tick) * v_tick;
        ELSE
          v_exit_price := round((
            v_entry_price
            + (CASE WHEN v_direction = 'Long' THEN 1 ELSE -1 END)
            * v_risk_points * (0.75 + random() * 0.35)
          ) / v_tick) * v_tick;
        END IF;
      ELSIF v_is_loss THEN
        IF random() < 0.78 THEN
          v_exit_price := v_stop_price;
        ELSE
          v_exit_price := round((
            v_entry_price
            + (CASE WHEN v_direction = 'Long' THEN -1 ELSE 1 END)
            * v_risk_points * (0.55 + random() * 0.5)
          ) / v_tick) * v_tick;
        END IF;
      ELSE
        v_exit_price := round((
          v_entry_price
          + (CASE WHEN random() < 0.5 THEN 1 ELSE -1 END) * v_tick * (1 + floor(random() * 2))
        ) / v_tick) * v_tick;
      END IF;

      v_actual_points := round(
        CASE WHEN v_direction = 'Long' THEN v_exit_price - v_entry_price ELSE v_entry_price - v_exit_price END,
        2
      );

      -- realized_rr = (actualPoints * targetedRr) / pointsTargeted (TradePointsAndRealizedRr)
      v_realized_rr := round((v_actual_points * v_targeted_rr) / nullif(v_points_targeted, 0), 2);
      IF v_full_tp THEN
        v_realized_rr := v_targeted_rr;
      END IF;
      IF v_realized_rr > v_targeted_rr THEN
        v_realized_rr := v_targeted_rr;
      END IF;
      IF v_realized_rr < -25 OR v_realized_rr > 25 THEN
        v_realized_rr := greatest(-25::numeric, least(25::numeric, v_realized_rr));
      END IF;

      IF v_early_exit AND v_actual_points > 0 THEN
        v_exit_rr := v_realized_rr;
        v_max_rr_reached := round(greatest(v_realized_rr, v_targeted_rr * (0.65 + random() * 0.45))::numeric, 2);
      ELSIF v_is_loss OR v_actual_points <= 0 THEN
        v_max_rr_reached := round((random() * v_targeted_rr * 0.85)::numeric, 2);
      ELSIF v_full_tp THEN
        v_max_rr_reached := round((v_targeted_rr * (1.0 + random() * 0.12))::numeric, 2);
      ELSE
        v_max_rr_reached := round(greatest(v_realized_rr, v_realized_rr * 1.08)::numeric, 2);
      END IF;

      v_gross_pnl := round(v_actual_points * v_point_value * v_contracts, 2);
      v_fees := round(v_fee_per_contract * v_contracts, 2);
      v_pnl := round(v_gross_pnl - v_fees, 2);

      v_dollar_risk := round(v_risk_points * v_point_value * v_contracts, 2);

      -- Psychology + discipline (stratified for iOS psychology charts)
      IF random() < v_psych_coverage THEN
        v_emotion_slot := ((v_trade_seq - 1) % array_length(v_emotions, 1)) + 1;
        v_confidence_slot := ((v_trade_seq + 1) % 5) + 1;
        v_exec_slot := ((v_trade_seq + 3) % 5) + 1;

        v_emotion := v_emotions[v_emotion_slot];
        IF random() < 0.12 THEN
          v_emotion := v_emotions[1 + floor(random() * array_length(v_emotions, 1))::integer];
        END IF;
        v_confidence := v_confidence_slot;
        v_exit_emotion := v_exit_emotions[((v_trade_seq + 2) % array_length(v_exit_emotions, 1)) + 1];
        v_execution_rating := v_exec_slot;

        IF v_consec_losses >= 2 THEN
          v_emotion := 'FOMO';
          v_exit_emotion := 'Frustrated';
        END IF;

        IF v_is_win AND v_execution_rating >= 4 THEN
          v_followed_plan := true;
        ELSIF v_is_loss OR v_consec_losses >= 2 THEN
          v_followed_plan := false;
        ELSE
          v_followed_plan := random() < 0.62;
        END IF;

        v_mistake_type := NULL;
        IF v_sleep_quality IS NOT NULL AND v_sleep_quality <= 2 AND (v_is_loss OR random() < 0.5) THEN
          v_mistake_type := v_mistakes[1 + ((v_trade_seq - 1) % array_length(v_mistakes, 1))];
          v_execution_rating := least(v_execution_rating, 3);
          v_followed_plan := false;
        ELSIF v_consec_losses >= 2 AND random() < 0.55 THEN
          v_mistake_type := 'Revenge trade';
          v_revenge_today := true;
          v_followed_plan := false;
          v_execution_rating := least(v_execution_rating, 2);
        ELSIF v_is_loss AND random() < 0.28 THEN
          v_mistake_type := v_mistakes[1 + floor(random() * array_length(v_mistakes, 1))::integer];
        END IF;

        v_psychology_notes := format(
          'Pre-trade felt %s. %s',
          lower(v_emotion),
          CASE WHEN v_mistake_type IS NOT NULL
            THEN 'Primary mistake today: ' || lower(v_mistake_type) || '.'
            ELSE 'No major mistake tag — review execution anyway.'
          END
        );
      ELSE
        v_confidence := NULL;
        v_emotion := NULL;
        v_exit_emotion := NULL;
        v_execution_rating := NULL;
        v_followed_plan := NULL;
        v_mistake_type := NULL;
        v_psychology_notes := NULL;
      END IF;

      IF v_followed_plan IS true AND v_execution_rating >= 4 AND random() < 0.55 THEN
        v_top_confluences := (ARRAY['VWAP, prior day high','Opening drive, liquidity sweep','Prior day low, imbalance'])[1 + floor(random() * 3)::integer];
      ELSE
        v_top_confluences := CASE WHEN random() < 0.45 THEN (ARRAY['VWAP, prior day high','Prior day low, imbalance'])[1 + floor(random() * 2)::integer] ELSE NULL END;
      END IF;

      v_notes := format(
        '[%s] %s Stop %s | target %s | points targeted %s | actual %s pts. Gross $%s, fees $%s, net $%s.',
        v_namespace,
        v_strategy,
        to_char(v_stop_price, 'FM999999990.00'),
        to_char(v_target_price, 'FM999999990.00'),
        to_char(v_points_targeted, 'FM999999990.00'),
        to_char(v_actual_points, 'FM999999990.00'),
        to_char(v_gross_pnl, 'FM999999990.00'),
        to_char(v_fees, 'FM999999990.00'),
        to_char(v_pnl, 'FM999999990.00')
      );

      INSERT INTO _tt_seed_trades (
        id, user_id, account_id, account_name, account_size, account_type, account_category,
        mode, trade_mode, ticker, direction, contracts,
        entry_price, exit_price, entry_time, exit_time, trade_date, date,
        pnl, rr, max_rr_reached, realized_rr, full_tp, early_exit, exit_rr,
        points, dollar_risk, session, strategy, notes, timeframe, news_event,
        confidence, emotion, followed_plan, market_condition, psychology_notes,
        exit_emotion, execution_rating, duration_seconds, duration_text,
        is_public, public_description, image_display_mode, reviewed,
        is_initial_import, import_source, import_fingerprint, created_at,
        mistake_type, trade_type, top_confluences
      ) VALUES (
        v_trade_id, v_user_id, v_account_id, v_acct_name, v_acct_size, v_acct_category, v_acct_category,
        v_acct_mode, v_acct_mode, v_ticker, v_direction, v_contracts,
        v_entry_price, v_exit_price, v_entry_ts, v_exit_ts, v_d, v_d,
        v_pnl, v_targeted_rr,
        v_max_rr_reached, v_realized_rr, coalesce(v_full_tp, false), coalesce(v_early_exit, false), v_exit_rr,
        v_points_targeted, v_dollar_risk, v_session, v_strategy, v_notes, v_timeframe, v_news_event,
        v_confidence, v_emotion, v_followed_plan, v_market_condition, v_psychology_notes,
        v_exit_emotion, v_execution_rating, v_duration_seconds, v_duration_text,
        false, '', 'fit', true,
        false, 'manual', v_fingerprint, v_entry_ts,
        v_mistake_type, v_trade_type, v_top_confluences
      );

      v_day_pnl := v_day_pnl + coalesce(v_pnl, 0);
      INSERT INTO _tt_day_trading_state (trade_date, day_pnl, revenge_today)
      VALUES (v_d, v_day_pnl, v_revenge_today)
      ON CONFLICT (trade_date) DO UPDATE SET
        day_pnl = EXCLUDED.day_pnl,
        revenge_today = EXCLUDED.revenge_today;

      IF v_pnl > 0 THEN
        v_consec_losses := 0;
        v_streak := v_streak + 1;
      ELSIF v_pnl < 0 THEN
        v_consec_losses := v_consec_losses + 1;
        v_streak := 0;
      END IF;
  END LOOP;

  -- Materialize check-ins from day table
  FOR v_d, v_sleep_hours, v_sleep_quality, v_morning_rating, v_stress_level, v_energy_level, v_focus_level, v_checkin_notes IN
    SELECT dc.trade_date, dc.sleep_hours, dc.sleep_quality, dc.morning_rating,
           dc.stress_level, dc.energy_level, dc.focus_level, dc.notes
    FROM _tt_day_checkin dc
    ORDER BY dc.trade_date
  LOOP
    v_checkin_seq := v_checkin_seq + 1;
    v_fingerprint := v_namespace || ':checkin:' || to_char(v_d, 'YYYY-MM-DD');
    v_checkin_id := (
      substr(md5(v_fingerprint), 1, 8)  || '-' ||
      substr(md5(v_fingerprint), 9, 4)  || '-' ||
      '4' || substr(md5(v_fingerprint), 13, 3) || '-' ||
      'b' || substr(md5(v_fingerprint), 17, 3) || '-' ||
      substr(md5(v_fingerprint), 21, 12)
    )::uuid;

    INSERT INTO _tt_seed_checkins (
      id, user_id, check_in_date, sleep_hours, sleep_quality, morning_rating,
      stress_level, energy_level, focus_level, notes
    ) VALUES (
      v_checkin_id, v_user_id, v_d, v_sleep_hours, v_sleep_quality, v_morning_rating,
      v_stress_level, v_energy_level, v_focus_level, v_checkin_notes
    );
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM _tt_seed_checkins c
    WHERE NOT EXISTS (
      SELECT 1 FROM _tt_seed_trades t WHERE t.trade_date = c.check_in_date
    )
  ) THEN
    RAISE EXCEPTION 'Internal seed error: check-in date without trades';
  END IF;

  SELECT count(*) FILTER (WHERE pnl > 0), coalesce(sum(pnl), 0)
  INTO v_win_count, v_total_pnl
  FROM _tt_seed_trades;

  RAISE NOTICE '--- % generated (mode=%) ---', v_namespace, v_run_mode;
  RAISE NOTICE 'account=% | % / % / % / $%',
    v_account_id, v_acct_name, v_acct_category, v_acct_mode, v_acct_size;
  RAISE NOTICE 'trades=%, check_ins=%, win%%=%, total_pnl=%',
    (SELECT count(*) FROM _tt_seed_trades),
    (SELECT count(*) FROM _tt_seed_checkins),
    round(100.0 * v_win_count / nullif((SELECT count(*) FROM _tt_seed_trades), 0), 1),
    round(v_total_pnl, 2);

  RAISE NOTICE 'emotion buckets (trades tagged): %',
    (SELECT jsonb_object_agg(emotion, n)
     FROM (
       SELECT emotion, count(*) AS n
       FROM _tt_seed_trades
       WHERE emotion IS NOT NULL
       GROUP BY emotion
     ) s);

  RAISE NOTICE 'check-in / trade-day overlap: % check-ins on % distinct trade dates',
    (SELECT count(*) FROM _tt_seed_checkins),
    (SELECT count(DISTINCT trade_date) FROM _tt_seed_trades);

  IF v_run_mode = 'dry_run' THEN
    RAISE NOTICE '--- preview trades (first %) ---', v_preview_limit;
    FOR v_i, v_d, v_ticker, v_direction, v_pnl, v_points, v_preview_rr IN
      SELECT row_number() OVER (ORDER BY trade_date, entry_time), trade_date, ticker, direction, pnl, points, rr
      FROM _tt_seed_trades
      ORDER BY trade_date, entry_time
      LIMIT v_preview_limit
    LOOP
      RAISE NOTICE '% | % % % tgt_pts=% pnl=% targeted_rr=%', v_i, v_d, v_ticker, v_direction, v_points, v_pnl, v_preview_rr;
    END LOOP;

    RAISE NOTICE '--- preview check-ins (first %) ---', v_preview_limit;
    FOR v_i, v_d, v_sleep_hours, v_morning_rating, v_stress_level IN
      SELECT row_number() OVER (ORDER BY check_in_date), check_in_date, sleep_hours, morning_rating, stress_level
      FROM _tt_seed_checkins
      ORDER BY check_in_date
      LIMIT v_preview_limit
    LOOP
      RAISE NOTICE '% | % sleep=% mood=% stress=%', v_i, v_d, v_sleep_hours, v_morning_rating, v_stress_level;
    END LOOP;

    RETURN;
  END IF;

  IF v_run_mode = 'apply' THEN
  -- Trades: idempotent on import_fingerprint (per user/account unique index when present)
    INSERT INTO public.trades (
      id, user_id, account_id, account_name, account_size, account_type, account_category,
      mode, trade_mode, ticker, direction, contracts,
      entry_price, exit_price, entry_time, exit_time, trade_date, date,
      pnl, rr, max_rr_reached, realized_rr, full_tp, early_exit, exit_rr,
      points, dollar_risk, session, strategy, notes, timeframe, news_event,
      confidence, emotion, followed_plan, market_condition, psychology_notes,
      exit_emotion, execution_rating, duration_seconds, duration_text,
      is_public, public_description, image_display_mode, reviewed,
      is_initial_import, import_source, import_fingerprint, created_at,
      mistake_type, trade_type, top_confluences
    )
    SELECT
      s.id, s.user_id, s.account_id, s.account_name, s.account_size, s.account_type, s.account_category,
      s.mode, s.trade_mode, s.ticker, s.direction, s.contracts,
      s.entry_price, s.exit_price, s.entry_time, s.exit_time, s.trade_date, s.date,
      s.pnl, s.rr, s.max_rr_reached, s.realized_rr, s.full_tp, s.early_exit, s.exit_rr,
      s.points, s.dollar_risk, s.session, s.strategy, s.notes, s.timeframe, s.news_event,
      s.confidence, s.emotion, s.followed_plan, s.market_condition, s.psychology_notes,
      s.exit_emotion, s.execution_rating, s.duration_seconds, s.duration_text,
      s.is_public, coalesce(s.public_description, ''), s.image_display_mode, s.reviewed,
      s.is_initial_import, s.import_source, s.import_fingerprint, s.created_at,
      s.mistake_type, s.trade_type, s.top_confluences
    FROM _tt_seed_trades s
    WHERE NOT EXISTS (
      SELECT 1 FROM public.trades t
      WHERE t.user_id = v_user_id
        AND t.import_fingerprint = s.import_fingerprint
    );

    GET DIAGNOSTICS v_inserted_trades = ROW_COUNT;

    INSERT INTO public.trader_daily_check_ins (
      id, user_id, check_in_date, sleep_hours, sleep_quality, morning_rating,
      stress_level, energy_level, focus_level, notes
    )
    SELECT
      c.id, c.user_id, c.check_in_date, c.sleep_hours, c.sleep_quality, c.morning_rating,
      c.stress_level, c.energy_level, c.focus_level, c.notes
    FROM _tt_seed_checkins c
    WHERE NOT EXISTS (
      SELECT 1 FROM public.trader_daily_check_ins x
      WHERE x.user_id = v_user_id AND x.check_in_date = c.check_in_date
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.trader_daily_check_ins x
      WHERE x.user_id = v_user_id
        AND x.check_in_date = c.check_in_date
        AND coalesce(x.notes, '') NOT LIKE ('[' || v_namespace || ']%')
        AND x.notes IS NOT NULL
        AND length(trim(x.notes)) > 0
    );

    GET DIAGNOSTICS v_inserted_checkins = ROW_COUNT;

    RAISE NOTICE '[%] apply inserted trades=% check_ins=% (skipped existing fingerprints/dates)',
      v_namespace, v_inserted_trades, v_inserted_checkins;

    IF (SELECT count(*) FROM public.trades t WHERE t.user_id = v_user_id AND t.import_fingerprint LIKE (v_namespace || ':%')) < greatest(1, v_trade_count - 5) THEN
      RAISE WARNING 'Seeded trade count lower than expected — re-run apply or check conflicts';
    END IF;
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- Post-run validation queries (read-only; safe to run after apply)
-- Replace seed_id if you changed CONFIG above.
-- -----------------------------------------------------------------------------
-- SELECT id, name, mode, category, account_size, note
-- FROM public.accounts
-- WHERE user_id = '30548db7-aeba-4b03-b3fb-4d9a1734ad03'::uuid
--   AND note LIKE '[test_trading_seed:local-dev-001]%';
--
-- SELECT count(*) AS seeded_trades, round(sum(pnl)::numeric,2) AS pnl
-- FROM public.trades
-- WHERE user_id = '30548db7-aeba-4b03-b3fb-4d9a1734ad03'::uuid
--   AND import_fingerprint LIKE 'test_trading_seed:local-dev-001:%';
--
-- SELECT count(*) AS seeded_checkins
-- FROM public.trader_daily_check_ins
-- WHERE user_id = '30548db7-aeba-4b03-b3fb-4d9a1734ad03'::uuid
--   AND notes LIKE '[test_trading_seed:local-dev-001]%';

COMMIT;