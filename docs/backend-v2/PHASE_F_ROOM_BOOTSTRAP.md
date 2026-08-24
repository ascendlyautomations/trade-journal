# Phase F — Trade Room / Community Loading Optimization

Evidence source: `Click Around 1.har` (~48 requests, ~19 fetches, concurrent 2–3s cluster).

## Before ownership map

| Concern | Owner | File | Trigger |
|--------|-------|------|---------|
| Joined rooms | `loadMemberRooms` | `app/community/page.tsx` | init effect `[user.id, roomParam, createMode]` |
| Selected room | `selectedRoomId` state | same | URL effect `[roomParam, rooms, loadingRooms]` |
| Sections | `loadSections` | same | room load effect |
| Messages (×2) | `fetchRoomMessages` pinned+main | same | room load / section click |
| Unread badges | `fetchUnreadByRoomIds` | same | `[rooms, user.id]` |
| **Duplicate unread** | same RPC again | same | mark-read effect after `loadingMessages=false` |
| Mark read | `markAllRoomMessagesSeenForUser` | same | mark-read effect |
| Notification enabled | `room_members` SELECT | same | `[selectedRoomId, needsJoin, user.id]` |
| Channel prefs | `fetchRoomChannelNotificationPrefs` | `lib/roomChannelNotificationPreferences.ts` | `[selectedRoomId, …, sections.length]` |
| Member counts (×2) | `loadMemberStats` HEAD×2 | `app/community/page.tsx` | `[selectedRoomId, isOwner, needsJoin]` |
| Presence | `createRoomPresenceSession` | `lib/roomPresence.ts` | `[selectedRoomId, needsJoin, user.id]` |
| Realtime | `room-{id}`, `typing-room-{id}` | `app/community/page.tsx` | room-scoped effects |
| Room images | `StorageImage` | sidebar 64+original, header 96+original | render |

### Confirmed HAR causes

1. **`get_room_unread_counts` ×2** — independent effects: (a) rooms list badges, (b) post-`mark_room_read` full refetch. Not Strict Mode alone.
2. **`mark_room_read` vs notification PATCH** — different semantics (read cursor vs push mute). Cold open uses SELECT for notification; PATCH is user toggle only.
3. **Two `room_messages`** — intentional pinned + non-pinned `Promise.all`, not duplication.
4. **Member counts ×2** — two PostgREST HEAD queries in `loadMemberStats` (active vs total).
5. **Room image ×3** — sidebar `originalSrc` + transform + header `fallbackToOriginal`.

## After architecture

```
Community room open (backendV2.rooms ON):
  loadRoomBootstrapForUser (single-flight + cache)
    → rpc_v1_room_bootstrap (preferred)
    → legacy controlled chain (missing RPC only)
  applyRoomBootstrapToCommunityState
  skip parallel notification/prefs/stats/mark-read effects
  presence: separate (unchanged lifecycle)
  realtime: unchanged (room channel + typing)
```

Flag OFF (default): legacy fan-out preserved except:
- mark-read patches `unreadByRoomId` locally (no second unread RPC)
- room images use `room-list-thumb` / `room-thumb` without original fallback

## RPC contract

**Function:** `rpc_v1_room_bootstrap(p_room_id, p_section_id?, p_message_limit?, p_mark_read?)`

**Returns:** room metadata, membership, sections, active section, channel prefs, owner member stats, unread count, pinned + main messages (bounded), pagination cursor, `mark_read.applied`.

**Security:** `SECURITY DEFINER`, `auth.uid()` membership check, `VOLATILE` when `p_mark_read=true`, grants `authenticated` only.

## Migration

- **File:** `supabase/migrations/20260821235029_rpc_v1_room_bootstrap.sql`
- **Rollback:** `supabase/rollbacks/20260821235029_rpc_v1_room_bootstrap_rollback.sql`

### Staging apply

```bash
npx supabase db push   # or apply SQL on staging only
node scripts/room-rpc-integration.test.mjs
BENCHMARK_ROOM_ID=<uuid> node scripts/benchmark-room-rpc.mjs
```

### Rollback

```bash
psql $DATABASE_URL -f supabase/rollbacks/20260821235029_rpc_v1_room_bootstrap_rollback.sql
```

## Enable (web)

```bash
# .env.local
NEXT_PUBLIC_BACKEND_V2_ROOMS=1
```

Or `localStorage.setItem("backendV2.rooms", "1")` + reload.

## Targets (staging, not production claims)

| Metric | Target |
|--------|--------|
| Warm bootstrap p50 | < 250ms |
| Warm bootstrap p95 | < 500ms |
| Requests per intentional warm room open | 1 bootstrap + 1 presence |
| Duplicate `get_room_unread_counts` on open | 0 |

## Tests

- `lib/backendV2/roomBootstrap.phaseF.test.ts`
- `scripts/room-rpc-integration.test.mjs` (skips without credentials)
- `scripts/benchmark-room-rpc.mjs`

## Remaining bottlenecks

- 60s unread polling interval (sidebar badges while on Community)
- REST presence heartbeat every 60s (audit item; Realtime presence not swapped in this phase)
- Section switch still uses 2× `room_messages` (legacy path)
- `loadMemberRooms` + list unread RPC on Community init (out of selected-room bootstrap scope)

## Confirmations

- **`native-ios/`** — not modified
- **Production SQL** — not applied automatically; migration prepared in-repo only

## Regression fix (20260822000716)

**Root cause:** `rpc_v1_room_bootstrap` selected `rooms.is_public`, `rooms.allow_members_chat`, and `rooms.created_at` — none exist on `public.rooms`.

**Immediate production recovery:** set `NEXT_PUBLIC_BACKEND_V2_ROOMS=0` and rebuild/redeploy (NEXT_PUBLIC is build-time embedded).

**Corrective migration:** `supabase/migrations/20260822000716_fix_room_bootstrap_schema_contract.sql`

**Client:** 42703 triggers session-scoped legacy fallback once; transient 5xx shows error UI; failed loads do not cache or overwrite cached messages.

## Final cleanup (fan-out removal)

When `backendV2.rooms` is ON:

- Legacy effects for notification setting, channel prefs, and member-count HEAD queries are **disabled** — bootstrap owns that state.
- Section switches call `rpc_v1_room_bootstrap` with `p_section_id` and `p_mark_read=false` (no direct `room_messages`).
- App notification rows (`notifications.read`) are marked once per intentional room open via coordinator (separate from `mark_room_read`).
- Presence upsert/read run in parallel and never block message render; stale room guard on presence callback.
