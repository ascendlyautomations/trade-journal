# iOS messaging & Supabase Realtime — load-test audit

Summary for **`realistic300_full`** harness design. Canonical app code lives under `native-ios/TradeTraxs/TradeTraxs/Data/`.

## Direct messages (DMs)

| Step | iOS / web behavior | Load harness mirror |
|------|-------------------|---------------------|
| Auth | JWT on PostgREST + Realtime `phx_join` payload `access_token` | Same |
| Inbox | `rpc_v2_messaging_bootstrap` (`p_limit` 40, `p_mark_message_notifications_read: false` on cold load) | HTTP |
| Thread open | `rpc_v1_conversation_thread_bootstrap` (`p_conversation_id`, `p_message_limit`, `p_mark_read`) | HTTP |
| Send | `POST /rest/v1/messages` `{ conversation_id, sender_id, content, image_url: null, channel: null }` — **RLS requires `channel` null** | HTTP insert; content prefixed `[loadtest:realistic300_full]` |
| Push | iOS `POST /api/messaging/notify-dm` after insert | **Skipped by default** (`LOADTEST_FULL_SKIP_PUSH=yes`) |
| Mark read | RPC `mark_conversation_read` | Optional HTTP (not on hot path) |

### Realtime routes (DM)

| Route key | Phoenix topic | `postgres_changes` |
|-----------|---------------|-------------------|
| `dm:{conversationID}` | `realtime:dm-{conversationID}` | `messages`, `message_reactions` — `conversation_id=eq.{id}` |
| `inbox-dms` | `realtime:inbox-dms` | `messages` — `conversation_id=in.(…)` (iOS top **40** inbox convos) |
| `dm-read:{userID}` | `realtime:dm-read-{userID}` | `conversation_member_preferences` — `user_id=eq.{userID}` |

Web DM typing uses Realtime **broadcast** (`typing` on `messages-{id}`); iOS does not — **not simulated**.

## Trade rooms

| Step | Behavior | Harness |
|------|----------|---------|
| Thread | Paginated `room_messages`; open room uses `watchRoomLive` | HTTP + Realtime |
| Send text | `INSERT room_messages` `{ room_id, user_id, content, section_id? }` | HTTP insert (tagged content) |
| Push | Web `POST /api/notifications/room-message`; **iOS send path does not call this today** | Skipped by default |
| Realtime | Topic `realtime:room-live-{roomID}` — `room_messages` + `room_message_reactions`, filter `room_id=eq.{id}` | `phx_join` |
| Inbox bump | `realtime:member-rooms` — `room_messages` `room_id=in.(…)` | Join when simulating inbox |
| Read cursors | `realtime:room-read-{userID}` — `room_members` | Optional join |

Presence is supported on room-live channels but **iOS `RoomConversationViewModel` passes `presenceTrack: nil`** — harness does not track presence.

## Activity / notifications Realtime

| Route | Topic | Table |
|-------|-------|-------|
| `notifications:{userID}` | `realtime:notifications-{userID}` | `notifications` — `user_id=eq.{userID}` |

Ordinary DMs do **not** insert Activity rows — push only. Room @mentions create Activity; harness avoids mention spam.

## WebSocket transport (iOS)

- URL: `{supabaseURL}/realtime/v1/websocket?apikey={anon}&vsn=1.0.0` (scheme **wss**).
- Join payload: `broadcast: { ack: false, self: false }`, `presence: { enabled: false }` unless presence key set, `postgres_changes: [{ event: "*", schema: "public", table, filter }]`.
- Heartbeat: Phoenix `heartbeat` on topic `phoenix` ~25s.

Implementation reference: `SupabaseProviders.swift` (`joinChannel`, `handleIncoming`).

## Server rate limits (Postgres triggers)

| Scope | Limits (phase-1 messaging scalability) |
|-------|----------------------------------------|
| `message_send` | 12 / 10s, 90 / 5m, 500 / 1h |
| `room_message` | 8 / 10s, 60 / 5m, 300 / 1h |
| Free plan DMs | **25 rolling 24h** per sender (`FREE_PLAN_DAILY_DM_LIMIT`) |

Harness enforces **per-VU send budgets** well below these (see `PROD_PERF_REALISTIC300_FULL.md`).

## Production read perf boundary

`loadtest/prod-read-perf.js` intentionally **excludes** messaging and Realtime. Full mix lives in **`loadtest/prod-realistic300-full.js`** only.
