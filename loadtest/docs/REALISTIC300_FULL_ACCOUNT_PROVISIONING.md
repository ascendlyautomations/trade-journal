# Realistic300_full — account sufficiency & provisioning plan

**Operator-only.** This document does not create accounts or production rows automatically.

## Are 50 perf accounts enough?

| Dimension | Assessment |
|-----------|------------|
| **Read load (300 VU)** | **Yes** — same model as `realistic300`: 300 sessions on 50 JWTs (~6 VUs/account). |
| **DM graph** | **Yes, if isolated** — you do not need 300 unique humans. You need enough **private 1:1 conversations** among perf emails so each active sender has a fixture conversation. Recommend **≥25 pairwise conversations** covering perfload02–50 (and anchor) so VU→user hash rarely hits an empty inbox. |
| **Trade rooms** | **Yes, if isolated** — **1–3 private rooms** with **only** perf members; all 50 in one private room is OK for read/Realtime member-rooms fan-in. |
| **Realtime fan-out** | **50 is sufficient** — iOS already multiplexes inbox watches (top 40 DM convos, member room IDs). Fixture should list ≤40 conversation IDs in `inboxRealtimeConversationIds` or rely on default (first N from fixture). |
| **Free-plan DM cap** | **Risk** — if perf users are **not Pro**, Postgres enforces **25 DMs / 24h / sender**. Default harness caps **3 DM sends/VU/run** × 300 VUs ≈ up to 900 attempts but only ~28% of dm_thread iterations send → typically **well under 25/user** if spread across accounts. **Recommendation:** confirm perf accounts are **Pro** (`is_pro`) or lower `LOADTEST_FULL_MAX_DM_SENDS_PER_VU` to **1** and `SEND_DM_IN_THREAD_CHANCE` is already 0.28 in code. |

**Conclusion:** **50 dedicated accounts are sufficient** for realistic300_full **when**:

1. All messaging stays inside the fixture (perf ↔ perf only).
2. Fixture is provisioned **before** the run (UUIDs in env JSON).
3. Push notify stays **off** (`LOADTEST_FULL_SKIP_PUSH=yes`).
4. Pro or conservative send caps respect free-tier DM limits.

Adding more than 50 accounts is **optional** (richer DM graph), not required for 300 VU concurrency.

## Safe provisioning plan (manual checklist)

### Phase 0 — Guardrails

- [ ] Use only `@tradetraxsdemo` / `perfload*` accounts from `PROD_PERF_ONEFIFTY_FIFTY_USERS.md`.
- [ ] Never use production UUIDs of real customer conversations or public community rooms.
- [ ] Name rooms/conversations internally (e.g. `"TT Loadtest Full v1"`) visible only to perf users.
- [ ] Record UUIDs via `node loadtest/scripts/discover-realistic300-full-fixture.mjs` → `loadtest/fixtures/realistic300-full-isolation.json` (gitignored).

### Phase 1 — Auth users (if not already 50)

Follow existing **`provision-prod-perf-accounts.py --onefifty`** (see `loadtest/docs/PROD_PERF_ONEFIFTY_FIFTY_USERS.md`). **Do not re-run** if 50 grants already verified.

### Phase 2 — Direct conversations (perf ↔ perf only)

For each pair (suggested minimum **25 pairs** among slots 2–50):

1. Sign in as user A (app or Supabase Auth password grant).
2. Create or **ensure** 1:1 conversation with user B using the same rules as production (`ensureDmConversation` / iOS `createDirectConversation`):
   - Insert `conversations` (`is_group: false`).
   - Insert two `conversation_participants` rows.
3. Verify **no** participant email is outside the perf list.
4. Add `{ "id": "<uuid>", "participantEmails": ["a@...", "b@..."] }` to fixture `directConversations`.

**Do not** seed initial message content unless needed for thread bootstrap; harness tags all writes.

### Phase 3 — Private trade rooms

1. As a perf user, create a **private** room (`rpc_v1_create_trade_room` or app UI) with `members_can_message: true`.
2. Add **only** perf accounts as `room_members` (batch invite or manual).
3. Note `room_id` and optional default `section_id` (channel).
4. Add to fixture `tradeRooms`.

Suggested layout:

| Room | Members |
|------|---------|
| `loadtest-full-alpha` | perfload02–17 |
| `loadtest-full-beta` | perfload18–33 |
| `loadtest-full-gamma` | perfload34–50 + anchor |

### Phase 4 — Validate fixture

k6 `setup()` requires **every** email in `LOADTEST_USERS_JSON` to appear in at least one fixture `participantEmails` or `memberEmails` entry (isolation gate). Easiest pattern: list all **50** perf emails as members of the three private trade rooms, plus pairwise DM fixtures for messaging variety.

```bash
./loadtest/scripts/verify-realistic300-full-env.sh
```

Fixes any fixture email not in `LOADTEST_USERS_JSON` or placeholder UUIDs.

### Phase 5 — Dry run

1. `LOADTEST_MAX_VUS=1` is **not** supported by the script (requires 300). Instead run **`realistic300`** read-only first at 300 VU.
2. Optional: single-VU smoke of messaging paths on **staging** using `phase-a-read.js` / manual PostgREST (production full test has no 1-VU mode).

### Phase 6 — After load test

```bash
node loadtest/scripts/cleanup-realistic300-full-data.mjs
```

Verify no remaining rows with `content` like `%[loadtest:realistic300_full]%` in fixture scopes.

## What we deliberately do not automate

- No migration for “loadtest” flags on rows (operator-owned fixture UUIDs).
- No auto-create of conversations in k6 `setup()` (would mutate prod during verify).
- No push notification enablement in default harness.
