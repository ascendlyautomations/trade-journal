# Backend V2 Phase 6.1 — Messaging Wiring Audit

**Status:** Root cause identified and fixed. Flag was **OFF at runtime** — wiring was correct but never reached.

## Audit answers

### 1. Was `backendV2.messages` enabled at runtime?

**No (before fix).** `.env.local` had Session/Dashboard/Feed `=1` but **no** `NEXT_PUBLIC_BACKEND_V2_MESSAGES` or `NEXT_PUBLIC_BACKEND_V2_MESSAGING`.

Canonical flag key: **`messages`** (telemetry name: `backendV2.messages`).  
Env aliases (both work): `NEXT_PUBLIC_BACKEND_V2_MESSAGES`, `NEXT_PUBLIC_BACKEND_V2_MESSAGING`.

**Fix applied:** `NEXT_PUBLIC_BACKEND_V2_MESSAGES=1` added to `.env.local`. **Restart Next** required (env is inlined at dev start).

### 2. Where is the feature flag first read?

`lib/backendV2/flags.ts` → `resolveBackendV2Flag("messages")` → static `process.env.NEXT_PUBLIC_BACKEND_V2_MESSAGES ?? process.env.NEXT_PUBLIC_BACKEND_V2_MESSAGING`.

Priority: test override > localStorage `backendV2.messages` > env > default **false**.

**First runtime gate on Messages load:** `app/(app)/messages/page.tsx` → `fetchConversations` → `isBackendV2Enabled("messages")`.

### 3. Was the Messages page still calling legacy bootstrap?

**Yes**, because the flag was OFF. Legacy path:

```
fetchUserDmConversations
  → conversation_participants
  → get_hidden_blocked_dm_conversation_ids
  → conversations (+ embed)
fetchUnreadCountsForConversations → get_conversation_unread_counts
fetchMutedConversationIds → conversation_member_preferences
```

This exactly matches the HAR.

### 4. Did `loadMessagingBootstrapForUser()` execute?

**No** — gated by `isBackendV2Enabled("messages")` returning false. The RPC loader was never invoked.

### 5. Did `MessagingRpcBootstrapRepository` instantiate?

**No** — only constructed inside `loadMessagingBootstrapForUser` after the flag check passes.

### 6. Did `BackendV2RpcClient.callKnown("rpc_v1_messaging_bootstrap")` execute?

**No** — same gate. RPC name constant: `BackendV2RpcNames.messaging` = `"rpc_v1_messaging_bootstrap"`.

### 7. Exact conditional that prevented RPC

```tsx
// app/(app)/messages/page.tsx — fetchConversations
if (isBackendV2Enabled("messages") && !isDemoModeActive()) {
  // RPC path — never entered when flag OFF
} else {
  // legacy REST fan-out — this ran
}
```

Secondary guard inside loader (throws if called with flag OFF):

```ts
if (!isBackendV2Enabled("messages")) {
  throw new Error("loadMessagingBootstrapForUser requires backendV2.messages flag ON")
}
```

### 8. If RPC ran, why legacy HAR?

N/A — RPC did **not** run. The HAR showed legacy because the **else branch** executed on every inbox load (initial, focus refresh, pull-to-refresh).

**Not caused by:** dual-run (OFF), demo mode, SQL, or missing repository code.

**Navbar note:** With Session ON, Navbar reads `getSessionBadges().dm_unread` and does **not** duplicate the full inbox fan-out on paint. Legacy HAR on `/messages` was from the Messages page itself.

---

## 9. Ownership chain (flag ON)

```
Messages page (app/(app)/messages/page.tsx)
  fetchConversations(userId, source)
    isBackendV2Enabled("messages")  ← lib/backendV2/flags.ts
    loadMessagingBootstrapForUser(supabase, userId)  ← lib/backendV2/messagingBootstrapRepository.ts
      messagingBootstrapCacheKey / readMessagingBootstrapCache  ← cache hit → 0 network
      getMessagingBootstrapFlight / beginMessagingBootstrapFlight  ← single-flight
      MessagingRpcBootstrapRepository.loadMessagesBootstrap()
        BackendV2RpcClient.callKnown(BackendV2RpcNames.messaging, decodeMessagesBootstrapV1)
          createSupabaseBackendV2Transport(supabase).rpc("rpc_v1_messaging_bootstrap", { p_limit, p_cursor? })
            supabase-js → POST …/rest/v1/rpc/rpc_v1_messaging_bootstrap
      writeMessagingBootstrapCache (first page only)
      patchSessionBadges({ dm_unread })  ← lib/backendV2/sessionBootstrapCache.ts (Session owns badge storage)
    map bootstrap → mapDmRowToInboxConversation → writeMessagesInboxSession
```

**No Provider/Hook layer** — same pattern as Feed Phase 5 (page owns fetch, repository owns network).

| Layer | Owner |
|-------|--------|
| UI / inbox state | Messages page |
| Session badge patch | Session cache (`patchSessionBadges`) |
| Bootstrap orchestration | `loadMessagingBootstrapForUser` |
| RPC network | `MessagingRpcBootstrapRepository` |
| Legacy REST (flag OFF / dual-run only) | `MessagingRestBootstrapRepository` + page else branch |

---

## 10. Fix applied

| Change | File |
|--------|------|
| Enable flag | `.env.local` → `NEXT_PUBLIC_BACKEND_V2_MESSAGES=1` |
| Wiring audit tests | `lib/backendV2/messagingBootstrap.phase6.test.ts` |
| Test script | `package.json` → `test:backend-v2` includes phase 6 |

**No SQL changes.**

---

## Expected HAR (after restart + hard refresh)

| Before (flag OFF) | After (flag ON) |
|-------------------|-----------------|
| `conversation_participants` | — |
| `get_hidden_blocked_dm_conversation_ids` | — |
| `conversations` | — |
| `get_conversation_unread_counts` | — |
| `conversation_member_preferences` | — |
| — | **1×** `POST …/rpc/rpc_v1_messaging_bootstrap` |

Remaining REST on `/messages` (expected, not inbox bootstrap):

- Session RPC (if not cached)
- Notifications PATCH (mark inbox seen on open)
- Realtime websocket (thread updates — separate from inbox bootstrap)

---

## Validation checklist

1. Restart Next (`npm run dev`) — **required** after `.env.local` change.
2. Hard refresh browser (disable cache).
3. Login → Dashboard → Messages.
4. Network filter: `rpc_v1_messaging_bootstrap` — exactly one POST.
5. Confirm no legacy 5-call fan-out on initial inbox load.
6. `npm run test:backend-v2` — 61 tests pass.

---

## Production readiness

**Wiring:** Ready after env flag + restart validation.  
**Recommendation:** Enable `NEXT_PUBLIC_BACKEND_V2_MESSAGES=1` in staging first; run dual-run briefly (`NEXT_PUBLIC_BACKEND_V2_DUAL_RUN=1`) to compare REST vs RPC, then cut over production flag.
