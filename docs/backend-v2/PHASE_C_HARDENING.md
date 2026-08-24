# Phase C Hardening — Pre-Deployment Report

**Status:** Prepared in-repo. **Not applied to production.**

---

## Caller compatibility matrix

| Caller | Location | RPC | Arguments | Cursor type | Mark-read |
|--------|----------|-----|-----------|-------------|-----------|
| Web inbox (V2 ON) | `app/(app)/messages/page.tsx` → `loadMessagingBootstrapForUser` | **`rpc_v2_messaging_bootstrap`** (fallback `rpc_v1_messaging_bootstrap`) | `p_limit`, `p_cursor`, `p_mark_message_notifications_read` | **text** composite `ISO\|uuid` (V2); V1 fallback uses timestamptz prefix | **Only** `source === "initial-load"` on page 0 |
| Web inbox (V2 OFF) | same page REST path | — (REST fan-out) | — | ISO string in client sort | Separate `markMessageNotificationsRead` PATCH |
| Web refresh/focus | `messages/page.tsx` | V2/V1 | `p_limit`, `p_cursor: null`, `p_mark_message_notifications_read: false` | null | **No** |
| Web pagination (future) | repository | V2/V1 | cursor from `next_cursor` | composite | **No** |
| Dual-run dev | `messagingBootstrapRepository.ts` | V2 + REST compare | — | — | **No** |
| Benchmark script | `scripts/benchmark-messaging-rpc.mjs` | V2 + V1 | explicit all three (V2) | null / composite | benchmark only when flag set |
| Integration tests | `scripts/messaging-rpc-integration.test.mjs` | V2 + V1 | explicit | null / composite | controlled cases only |
| **native-ios** | `BackendV2Versioning.swift` (name constant only) | **`rpc_v1_messaging_bootstrap`** | *Not invoked by current Swift bootstrap* — uses `MessageRepository.conversations` REST | timestamptz if used later | **Untouched** |
| API/server routes | — | **None** | — | — | — |
| Old V1 clients | any | `rpc_v1_messaging_bootstrap` | `p_limit`, `p_cursor timestamptz` | timestamptz | separate PATCH (client-owned) |

---

## SECURITY DEFINER audit (`rpc_v2_messaging_bootstrap`)

| Check | Status |
|-------|--------|
| Reject `auth.uid() is null` | ✓ raises `42501 not_authenticated` |
| All reads scoped to viewer | ✓ `membership` filters `conversation_participants.user_id = v_uid` |
| Notification UPDATE scoped | ✓ `where n.user_id = v_uid and n.type = 'message' and n.read = false` |
| Mark-read only page 0 | ✓ requires `p_cursor is null or btrim = ''` |
| Blocked conversations | ✓ `get_hidden_blocked_dm_conversation_ids()` unchanged |
| Muted unread zero | ✓ case expression + `dm_unread_total` excludes muted |
| `search_path` | ✓ `public, pg_temp` on V2 + helpers |
| Fully qualified refs | ✓ `public.*` tables/functions |
| REVOKE PUBLIC | ✓ all V2 functions |
| REVOKE anon | ✓ V2 RPC + helpers |
| GRANT authenticated only | ✓ V2 RPC |
| Helpers security | `_v2_messaging_*` SECURITY INVOKER, revoked from public/anon |
| Cross-user mutation | **Not possible** — no user_id parameter; UPDATE keyed to `auth.uid()` |

**V1 unchanged:** `rpc_v1_messaging_bootstrap(integer, timestamptz)` remains as deployed.

---

## Notification mutation semantics

| Scenario | Marks notifications? |
|----------|---------------------|
| Intentional first inbox load (`initial-load`, page 0) | **Yes** (V2 in-RPC; V1 PATCH fallback) |
| Cache hit on remount | **No** — cache bypassed when `markMessageNotificationsRead` true |
| Refresh / focus / pull-to-refresh | **No** — `markMessageNotificationsRead: false` |
| Pagination (`p_cursor` set) | **No** — SQL guard + client never passes flag |
| Prefetch / warming | **No** — Messages RPC only from page effect |
| Retry same inbox open | **Idempotent** — already-read rows not updated; count reflects actual updates |
| Return field | `message_notifications_marked_read` (actual row count) |

---

## Migration filenames

| File | Purpose |
|------|---------|
| `supabase/migrations/20260821014228_rpc_v2_messaging_bootstrap.sql` | **Apply** — V2 RPC + index + helpers |
| `supabase/migrations/rollback/20260821014228_rpc_v2_messaging_bootstrap_rollback.sql` | **Rollback** — drops V2 only |
| `supabase/migrations/20260821090000_rpc_v1_messaging_bootstrap.sql` | **Unchanged** — legacy clients |

**Removed (pre-hardening):** `20260821013632_rpc_v1_messaging_bootstrap_optimize.sql` (would have broken V1 overload).

---

## Local/staging integration tests

Docker/Supabase local stack **not available** in this environment (`docker: command not found`).

Script prepared: `node scripts/messaging-rpc-integration.test.mjs`

**Result here:** `SKIP` — requires `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `MESSAGING_TEST_USER_A_JWT`.

After staging apply, run:

```bash
SUPABASE_URL=... SUPABASE_ANON_KEY=... \
MESSAGING_TEST_USER_A_JWT=... \
MESSAGING_TEST_USER_B_JWT=... \
node scripts/messaging-rpc-integration.test.mjs
```

Covers: anonymous reject, authenticated inbox, V1 legacy, pagination no mutation, no duplicates, muted zero, cross-user isolation, 30-run benchmark.

---

## Benchmark results

**Not run** — no staging credentials in this environment.

Run after migration apply:

```bash
SUPABASE_URL=... BENCHMARK_USER_JWT=... node scripts/benchmark-messaging-rpc.mjs
```

Reports median/p95/max for V2 inbox, V2 inbox+mark-read, V1 legacy, page 2.

---

## Request-count comparison

| Inbox open | Pre-Phase C (V2 ON) | Post-hardening (V2 deployed) | V2 unavailable (V1 fallback) |
|------------|---------------------|------------------------------|------------------------------|
| Network requests | 2 (PATCH + RPC) | **1** (V2 RPC) | 2 (V1 RPC + PATCH) |
| Refresh | 1 RPC | 1 RPC | 1 RPC |

---

## Production rollout order

1. Apply `20260821014228_rpc_v2_messaging_bootstrap.sql` on **staging**
2. Run integration script + benchmark (30 warm); confirm median &lt;250ms, p95 &lt;500ms
3. Deploy **web app** (calls V2 with V1 fallback — safe before/after migration)
4. Validate inbox open: one request, notifications cleared, no duplicate conversations on page 2
5. Apply same migration on **production** during low-traffic window
6. Monitor RPC latency + error rate for `rpc_v2_messaging_bootstrap`
7. If rollback needed: run `rollback/20260821014228_rpc_v2_messaging_bootstrap_rollback.sql` — web falls back to V1 automatically

**Do not** deploy web-only rollback without SQL rollback if V2 is live (web expects V2 fields like composite cursor).

---

## native-ios

**Inspected, untouched.**

- `BackendV2Versioning.swift` still references `rpc_v1_messaging_bootstrap`
- `MessagingBootstrap.swift` uses REST `MessageRepository.conversations`, not Postgres RPC
- No Swift changes in this hardening pass

---

## Tests / build

- `npm run test:backend-v2` — run after changes
- `npm run build` — run after changes
