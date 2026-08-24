# Phase F2 — Community idle network & Realtime reliability

## Unread badges

- **Removed:** 60-second `get_room_unread_counts` polling and visibility-triggered refetch while connected.
- **Kept:** One initial RPC after joined rooms load.
- **Added:** Event-driven patches via:
  - `community-unread-{userId}` channel — `room_messages` INSERT per joined room (`room_id=eq.{id}`).
  - Shared `notif-shared-{userId}` — `room_mention` / `room_join` notification INSERT/UPDATE.
- **Reconciliation:** At most one bounded RPC after Realtime reconnect or returning from ≥60s hidden **only if** events may have been missed (`needsReconcile` flag).
- **Open room:** Does not increment unread after intentional mark-read; bootstrap/read clears badge locally.

Ordinary room messages do **not** create Activity rows — sidebar unread for non-mention messages relies on `room_messages` INSERT Realtime (member RLS).

## Reactions

**Root cause:** `message_id=in.(uuid1,uuid2,...)` postgres_changes subscription fails on Realtime (system error); single `message_id=eq.{uuid}` works. Channel was recreated whenever visible message IDs changed.

**Fix:** Migration `20260822104500_room_message_reactions_room_id_realtime.sql` adds denormalized `room_id` + stable filter `room_id=eq.{roomId}` on `room-live-{roomId}` channel. Client gates by loaded message IDs.

**PGRST201 regression (20260823010000):** Composite FK + legacy `message_id` FK caused ambiguous PostgREST embeds on message INSERT `.select()`. Drop redundant `room_message_reactions_message_id_fkey`; keep composite with CASCADE. Client embeds use `room_message_reactions!room_message_reactions_message_room_fkey(...)`.

## Presence

- **Flag:** `NEXT_PUBLIC_BACKEND_V2_ROOM_PRESENCE=1` or `localStorage backendV2.roomPresence=1`
- **When ON:** Realtime Presence on `room-live-{roomId}` — `track()` once after SUBSCRIBED; no REST heartbeat/read/delete.
- **When OFF:** Existing REST `room_presence` session (fallback).
- **Semantic difference:** REST uses `last_seen` + ~135s threshold; Presence is connection/tab based.

## Channel inventory (after)

| Channel | Purpose |
|---------|---------|
| `notif-shared-{userId}` | Activity notifications (shared) |
| `community-unread-{userId}` | Sidebar unread (joined room message INSERTs) |
| `room-live-{roomId}` | Selected room messages + reactions (+ presence when flagged) |
| `typing-room-{roomId}` | Typing broadcast |

Section switching does **not** recreate `room-live-{roomId}`.

## Rollout

1. Apply `20260822104500_room_message_reactions_room_id_realtime.sql` in staging (if not already).
2. Apply **`20260822220000_enforce_reaction_message_room_integrity.sql`** in staging before production.
3. Rebuild with `NEXT_PUBLIC_BACKEND_V2_ROOM_PRESENCE=1` for Presence validation.
4. Run `scripts/room-reaction-integrity.test.mjs` against staging credentials.
5. Capture 5-minute idle HAR — zero REST presence when Presence flag ON.

## Security correction (20260822220000)

- Trigger `room_message_reactions_enforce_message_room_integrity` — **SECURITY INVOKER**, derives `room_id` from `room_messages`, rejects client mismatches.
- Composite FK `(message_id, room_id) → room_messages(id, room_id)`.
- RLS uses `(select auth.uid())` + INSERT message/room consistency check.
- Publication rollback does **not** remove `room_message_reactions` from `supabase_realtime` (may pre-date Phase F2).

## Rollback

- Web: disable flags; redeploy prior build.
- SQL (reverse order): `20260822220000_*_rollback.sql`, then `20260822104500_*_rollback.sql` (see publication note in rollback file).
