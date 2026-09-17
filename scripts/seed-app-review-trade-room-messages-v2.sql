-- =============================================================================
-- TradeTraxs App Review — Trade Room conversation seed V2 (MANUAL RUN ONLY)
-- Namespace: app_review_seed:v2:room_messages
--
-- >>> REVIEW ACCOUNT (viewer / room owner) <<<
-- TARGET_USER_ID:        d3aeace4-e2a5-4679-b47d-23d40d6e2c59
-- EXPECTED_REVIEW_EMAIL: iosreview@tradetraxs.com
--
-- Creates a community Trade Room owned by the review user and seeds a realistic
-- pre-market → RTH futures desk thread between existing profiles:
--   @nrltrades, @jayketrades, @tradetraxs (avatars come from their profiles).
--
-- Requires those three usernames to exist in public.profiles (production team accounts).
-- Run in Supabase SQL editor with service role / "Run without RLS" if prompted.
-- Safe to re-run (idempotent room, members, messages by fixed UUIDs).
-- =============================================================================

BEGIN;

-- Fixed IDs (do not change — rollback block at bottom references these)
-- Room slug: app-review-bias-desk

CREATE TEMP TABLE _app_review_v2_room_messages (
  id uuid PRIMARY KEY,
  sender text NOT NULL CHECK (sender IN ('nrl', 'jay', 'tt')),
  content text NOT NULL,
  created_at timestamptz NOT NULL,
  parent_id uuid NULL REFERENCES _app_review_v2_room_messages (id)
) ON COMMIT DROP;

INSERT INTO _app_review_v2_room_messages (id, sender, content, created_at, parent_id) VALUES
('f1a2b3c4-d5e6-4789-a012-345678900001'::uuid, 'nrl',
 'Morning desk. ES holding above yesterday VAH and NQ is leading. Bias stays long while we hold 6520 ES — lose 6508 and I flip neutral.',
 '2026-09-11T08:42:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900002'::uuid, 'jay',
 'Same read. Plan is two MNQ longs off a 6520 retest, stop 6512, targets 6540 and 6555. Not chasing the open drive.',
 '2026-09-11T08:48:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900003'::uuid, 'tt',
 'Good morning everyone. Log your pre-market bias in the journal before the first entry — it makes the session review cards much cleaner later.',
 '2026-09-11T08:51:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900004'::uuid, 'nrl',
 'Macro calendar is light until 10am. VIX is compressed so I am sizing down on the first push — expect a two-way open.',
 '2026-09-11T09:05:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900005'::uuid, 'jay',
 'Risk cap today is 0.4R per clip. One process mistake and I am done for the session.',
 '2026-09-11T09:06:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900006'::uuid, 'jay',
 '6522 is marked for the first entry if we dip and reclaim.',
 '2026-09-11T09:06:30-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900007'::uuid, 'nrl',
 'CL is soft but not dragging index delta yet. Keeping focus on ES/NQ correlation.',
 '2026-09-11T09:18:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900008'::uuid, 'tt',
 'Anyone scaling partials at the overnight high or holding full size into the trend leg?',
 '2026-09-11T09:32:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900009'::uuid, 'jay',
 'Took one contract off at 6538, runner targets the VWAP extension. Still aligned with the morning bias.',
 '2026-09-11T09:41:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900010'::uuid, 'nrl',
 'Still in from the open drive — trailing under 5m structure. 6535 reclaim was my add signal.',
 '2026-09-11T09:44:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900011'::uuid, 'tt',
 'Solid execution on both sides. Tag the session as New York AM in the journal if you have not already.',
 '2026-09-11T09:52:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900012'::uuid, 'jay',
 'Tagged. Entry emotion was focused — slight FOMO on the add but I passed on a third clip.',
 '2026-09-11T10:03:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900013'::uuid, 'nrl',
 'Lunch chop zone now. Flat unless we accept above 6545 with volume.',
 '2026-09-11T11:28:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900014'::uuid, 'jay',
 'Out completely. +2.1R net. Not forcing anything into the midday drift.',
 '2026-09-11T11:35:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900015'::uuid, 'tt',
 'That is the process. Drop your recap trade when you get a minute — helps the desk see what worked.',
 '2026-09-11T11:40:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900016'::uuid, 'nrl',
 'Posted my ES screenshot — breaker fill into continuation. Same pocket we flagged at 6520 pre-market.',
 '2026-09-11T12:05:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900017'::uuid, 'jay',
 'That is the same pocket I missed — respect the patience on the retest.',
 '2026-09-11T12:08:00-04:00'::timestamptz,
 'f1a2b3c4-d5e6-4789-a012-345678900016'::uuid),
('f1a2b3c4-d5e6-4789-a012-345678900018'::uuid, 'tt',
 'Midday update: bias shifts neutral below 6518 on ES. Size down if you re-engage.',
 '2026-09-11T12:20:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900019'::uuid, 'nrl',
 'Back at the desk ~1:50pm. Watching for a failed breakdown long if we sweep lows and reclaim.',
 '2026-09-11T13:52:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900020'::uuid, 'jay',
 'Only taking a quick MNQ short if we lose 6525 with momentum — in and out, no hero trades.',
 '2026-09-11T13:58:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900021'::uuid, 'nrl',
 'Short worked — covered 6519 for 1R. Calling it a day after that.',
 '2026-09-11T14:22:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900022'::uuid, 'tt',
 'Nice finish. Link broker import tonight if you want fills attached automatically on the next session.',
 '2026-09-11T14:30:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900023'::uuid, 'jay',
 'Will do after the close. See everyone pre-market tomorrow.',
 '2026-09-11T15:05:00-04:00'::timestamptz, null),
('f1a2b3c4-d5e6-4789-a012-345678900024'::uuid, 'nrl',
 'Same here — bias sheet is updated for tomorrow. Good trading all.',
 '2026-09-11T15:08:00-04:00'::timestamptz, null);

DO $$
DECLARE
  target_user_id uuid := 'd3aeace4-e2a5-4679-b47d-23d40d6e2c59'::uuid;
  expected_review_email text := 'iosreview@tradetraxs.com';
  v_room_id uuid := 'f1a2b3c4-d5e6-4789-a012-3456789abcde'::uuid;
  v_section_id uuid := 'f1a2b3c4-d5e6-4789-a012-3456789abcdf'::uuid;
  v_room_slug text := 'app-review-bias-desk';
  auth_email text;
  v_nrl uuid;
  v_jay uuid;
  v_tt uuid;
  inserted_messages int := 0;
  r record;
  v_user_id uuid;
BEGIN
  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid target_user_id.';
  END IF;

  SELECT u.email INTO auth_email FROM auth.users u WHERE u.id = target_user_id;
  IF auth_email IS NULL THEN
    RAISE EXCEPTION 'auth.users has no row for %', target_user_id;
  END IF;
  IF lower(trim(auth_email)) <> lower(trim(expected_review_email)) THEN
    RAISE EXCEPTION 'Email mismatch for review account.';
  END IF;

  SELECT p.id INTO v_nrl
  FROM public.profiles p
  WHERE lower(trim(p.username)) = 'nrltrades'
  LIMIT 1;
  SELECT p.id INTO v_jay
  FROM public.profiles p
  WHERE lower(trim(p.username)) = 'jayketrades'
  LIMIT 1;
  SELECT p.id INTO v_tt
  FROM public.profiles p
  WHERE lower(trim(p.username)) = 'tradetraxs'
  LIMIT 1;

  IF v_nrl IS NULL THEN
    RAISE EXCEPTION 'Profile @nrltrades not found — required for seeded senders.';
  END IF;
  IF v_jay IS NULL THEN
    RAISE EXCEPTION 'Profile @jayketrades not found — required for seeded senders.';
  END IF;
  IF v_tt IS NULL THEN
    RAISE EXCEPTION 'Profile @tradetraxs not found — required for seeded senders.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = target_user_id) THEN
    RAISE EXCEPTION 'Review profile missing — run seed-app-review-trading-history-v2.sql first.';
  END IF;

  -- One community room per owner (unique index on owner_user_id). Reuse if review user already owns a room.
  SELECT r.id INTO v_room_id
  FROM public.rooms r
  WHERE r.owner_user_id = target_user_id
  ORDER BY r.created_at NULLS LAST
  LIMIT 1;

  IF v_room_id IS NULL THEN
    INSERT INTO public.rooms (
      id,
      name,
      description,
      slug,
      owner_user_id,
      show_on_profile,
      is_private,
      room_kind,
      join_policy,
      members_can_message,
      members_can_share_trades,
      members_can_share_media,
      discovery_tags
    )
    VALUES (
      'f1a2b3c4-d5e6-4789-a012-3456789abcde'::uuid,
      'Morning Bias Desk',
      '[app_review_seed:v2:room_messages] Futures session desk for App Review — ES/NQ bias, risk, and recap.',
      v_room_slug,
      target_user_id,
      true,
      false,
      'community',
      'open',
      true,
      true,
      true,
      ARRAY['Futures', 'Indices', 'App Review']::text[]
    );
    v_room_id := 'f1a2b3c4-d5e6-4789-a012-3456789abcde'::uuid;
  END IF;

  SELECT s.id INTO v_section_id
  FROM public.room_sections s
  WHERE s.room_id = v_room_id
    AND lower(trim(s.name)) = 'general'
  ORDER BY s.position NULLS LAST
  LIMIT 1;

  IF v_section_id IS NULL THEN
    INSERT INTO public.room_sections (room_id, name, position, allow_members_chat)
    VALUES (v_room_id, 'general', 1, true)
    RETURNING id INTO v_section_id;
  END IF;

  PERFORM public.ensure_room_member_tags_defaults(v_room_id);

  -- Review user + three conversation participants (avatars from profiles).
  FOR v_user_id IN SELECT unnest(ARRAY[target_user_id, v_nrl, v_jay, v_tt])
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.room_members rm
      WHERE rm.room_id = v_room_id AND rm.user_id = v_user_id
    ) THEN
      INSERT INTO public.room_members (room_id, user_id, notification_enabled, left_at)
      VALUES (v_room_id, v_user_id, true, null);
    ELSE
      UPDATE public.room_members rm
      SET left_at = null, notification_enabled = true
      WHERE rm.room_id = v_room_id AND rm.user_id = v_user_id;
    END IF;
  END LOOP;

  FOR r IN
    SELECT m.id, m.sender, m.content, m.created_at, m.parent_id
    FROM _app_review_v2_room_messages m
    ORDER BY m.created_at, m.id
  LOOP
    v_user_id := CASE r.sender
      WHEN 'nrl' THEN v_nrl
      WHEN 'jay' THEN v_jay
      WHEN 'tt' THEN v_tt
      ELSE null
    END;

    IF EXISTS (SELECT 1 FROM public.room_messages x WHERE x.id = r.id) THEN
      CONTINUE;
    END IF;

    INSERT INTO public.room_messages (
      id,
      room_id,
      section_id,
      user_id,
      content,
      created_at,
      pinned,
      parent_message_id,
      seen_by
    ) VALUES (
      r.id,
      v_room_id,
      v_section_id,
      v_user_id,
      r.content,
      r.created_at,
      false,
      r.parent_id,
      jsonb_build_array(target_user_id::text)
    );

    inserted_messages := inserted_messages + 1;
  END LOOP;

  RAISE NOTICE 'App Review Trade Room v2: room_id=%, slug=%, messages_inserted=%',
    v_room_id, v_room_slug, inserted_messages;
  RAISE NOTICE 'Senders: nrltrades=%, jayketrades=%, tradetraxs=%', v_nrl, v_jay, v_tt;
END $$;

COMMIT;

-- =============================================================================
-- OPTIONAL ROLLBACK (separate transaction)
-- =============================================================================
-- BEGIN;
-- DELETE FROM public.room_message_reactions
--  WHERE message_id IN (
--    SELECT id FROM public.room_messages
--     WHERE room_id = 'f1a2b3c4-d5e6-4789-a012-3456789abcde'::uuid
--  );
-- DELETE FROM public.room_messages
--  WHERE room_id = 'f1a2b3c4-d5e6-4789-a012-3456789abcde'::uuid;
-- DELETE FROM public.room_members
--  WHERE room_id = 'f1a2b3c4-d5e6-4789-a012-3456789abcde'::uuid;
-- DELETE FROM public.room_sections
--  WHERE room_id = 'f1a2b3c4-d5e6-4789-a012-3456789abcde'::uuid;
-- DELETE FROM public.rooms
--  WHERE id = 'f1a2b3c4-d5e6-4789-a012-3456789abcde'::uuid;
-- COMMIT;
