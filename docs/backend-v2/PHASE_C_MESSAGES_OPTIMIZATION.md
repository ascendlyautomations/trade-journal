# Phase C — Messages Inbox & Thread Optimization

Web-only Messages performance phase. Trade Rooms consolidation and cross-app Realtime phases are **not** started here.

## Status

| Item | State |
|------|--------|
| Optimization migration | `supabase/migrations/20260821013632_rpc_v1_messaging_bootstrap_optimize.sql` |
| Rollback SQL | `supabase/migrations/rollback/20260821013632_rpc_v1_messaging_bootstrap_rollback.sql` |
| Applied to production | **No** |
| HAR baseline | HAR 8 ~211ms RPC + ~224ms PATCH; HAR 9 ~2.22s both (simultaneous) |
| native-ios/ touched | **No** |

---

## C1 — Frozen contracts (pre-optimization)

### `rpc_v1_messaging_bootstrap`

| Property | Value |
|----------|--------|
| Args | `p_limit integer` (default 40, max 80), `p_cursor timestamptz` (default null) |
| Returns | `jsonb` |
| Security | `SECURITY DEFINER` (matches `get_conversation_unread_counts`) |
| search_path | `public` |
| Grants | `REVOKE ALL FROM public`; `GRANT EXECUTE TO authenticated` |

### Top-level JSON keys

**meta:** `contract_version`, `server_time`, `viewer_id`

**data:** `conversations`, `peers`, `dm_unread_total`, `muted_ids`, `next_cursor`, `page_meta`

### Conversation shape

`id`, `is_group`, `is_pinned`, `name`, `avatar_url`, `last_message`, `last_message_at`, `unread_count`, `muted`, `participants[]`

### Related functions (unchanged)

- `get_conversation_unread_counts(uuid[])` — unread boundary via `last_read_at` / `last_read_message_id`
- `get_hidden_blocked_dm_conversation_ids()` — block/privacy
- `mark_conversation_read(uuid)` — thread open (client)
- Notification mark-read — client PATCH on `notifications` (`type=message`, `read=false`)

### Thread loading (no dedicated thread RPC)

- `queryDmMessages` — bounded select with profile embed
- Keyset pagination: `created_at` + `id` for older messages
- Initial page: `messagePageSize + 1` rows

---

## C2 — Internal cost breakdown (before)

| Section | Pattern | Relative cost |
|---------|---------|---------------|
| Blocked filter | `get_hidden_blocked_dm_conversation_ids()` | Low |
| Membership | `conversation_participants` by `user_id` | Low (indexed) |
| **Unread** | `get_conversation_unread_counts(ALL membership)` — scans messages per conversation | **High** |
| Conversation sort | `row_number()` over all membership rows | Medium at scale |
| Participants | Set-based `jsonb_agg` for **page IDs only** | Low |
| Last message | Denormalized on `conversations` — no per-convo message scan | Low |
| Page-open PATCH | Separate REST UPDATE on `notifications` | Medium + **contention with RPC** |

HAR 9 (~2.22s each, simultaneous start) suggests **connection/pool contention** between PATCH and RPC.

---

## C3 — Optimized architecture

### After Phase C RPC

```
auth.uid() once
→ optional mark message notifications read (inbox open, page 0 only, same transaction)
→ blocked + membership + muted CTEs
→ rank conversations with composite keyset cursor (last_message_at | id)
→ page bounded to limit+1
→ single get_conversation_unread_counts(membership) for totals + page join
→ participants + peers hydration for page IDs only
→ stable JSON + message_notifications_marked_read count
```

### Changes

1. **Composite cursor** — `ISO|conversation_uuid` (legacy timestamp input supported)
2. **Deterministic ordering** — pinned → `last_message_at` → `id`
3. **Consolidated mark-read** — `p_mark_message_notifications_read boolean` (default false); only when `p_cursor is null`
4. **Partial index** — `notifications(user_id) WHERE read=false AND type='message'`
5. **Single unread scan** — one `get_conversation_unread_counts` call (page joins same CTE)

### Thread path (unchanged, already bounded)

- Keyset load via `queryDmMessages`
- Realtime on thread: one channel per conversation (`messages-{id}`) with cleanup on unmount
- **Inbox page has no Realtime subscriptions**

---

## C4 — Client changes

| Change | File |
|--------|------|
| Inbox mark-read via RPC when V2 ON | `messages/page.tsx` |
| Fallback PATCH when V2 OFF | `messageNotificationReadSync.ts` (unchanged) |
| Stale response rejection | `inboxRequestGenerationRef` |
| Open thread: no full inbox refetch | `openConversation` — local unread patch only |
| RPC args | `messagingBootstrapRepository.ts` |

**Target request count on inbox open (V2 ON):** **1 RPC** (includes notification mark-read when flag set)

---

## C5 — Realtime inventory

| Location | Channel | Behavior |
|----------|---------|----------|
| Inbox `/messages` | **None** | N/A |
| Thread `/messages/[id]` | `messages-{conversationId}` | postgres_changes + typing broadcast; duplicate channel removed on subscribe |
| Navbar | `notif-shared-{userId}` | Activity notifications (not Messages-owned) |

No full inbox refetch on new message — thread patches + `CONVERSATION_UPDATED_EVENT` for inbox preview.

---

## Validation

```bash
npm run test:backend-v2   # 133 tests
npm run build
```

Benchmark (local/staging after migration apply):

```bash
SUPABASE_URL=... BENCHMARK_USER_JWT=... node scripts/benchmark-messaging-rpc.mjs
```

Rollback cycle: apply optimize → validate → `rollback/20260821013632_...` → validate → reapply.

---

## Remaining bottlenecks

1. `get_conversation_unread_counts` over full membership — required for accurate `dm_unread_total`
2. HAR variance — measure post-consolidation on staging
3. Thread shared-content preview fetches (trade/post embeds) — out of inbox RPC scope
4. Cross-app Realtime consolidation — dedicated future phase

---

## Confirmations

- Auth, Session, Dashboard, Feed RPCs, FreePlan, Trade Rooms, `native-ios/` — **untouched**
- RLS semantics — **preserved** (DEFINER helpers unchanged)
- **Not applied to production**
