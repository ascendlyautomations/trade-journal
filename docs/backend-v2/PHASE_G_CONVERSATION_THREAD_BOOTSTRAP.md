# Phase G — Personal Conversation Thread Bootstrap

Replace the legacy `/messages/[identifier]` waterfall with one canonical bounded bootstrap plus stable Realtime.

## Flag

```bash
NEXT_PUBLIC_BACKEND_V2_MESSAGE_THREADS=1
```

Or `localStorage.setItem("backendV2.messageThreads", "1")` then reload.

Flag **OFF** preserves the complete legacy thread path unchanged.

## RPC

`rpc_v1_conversation_thread_bootstrap(p_conversation_id, p_message_limit, p_cursor, p_mark_read)`

- **VOLATILE** — may call `mark_conversation_read` when `p_mark_read = true`
- **SECURITY DEFINER** with `(select auth.uid())` membership gate via `is_conversation_participant`
- Returns conversation metadata, participants, notification preference, DM block status, bounded messages (viewer deletion filtering inline), keyset cursor, mark-read + conversation-target notification counts

Does **not** modify `rpc_v2_messaging_bootstrap` (inbox).

## Client architecture

| Module | Role |
|--------|------|
| `conversationThreadBootstrapRepository.ts` | RPC + controlled legacy fallback |
| `conversationThreadBootstrapCache.ts` | Per viewer/conversation cache |
| `conversationThreadBootstrapSingleFlight.ts` | Process-wide dedupe |
| `conversationThreadInboxSeed.ts` | Inbox cache header seed + username aliases |
| `conversationThreadBootstrapApply.ts` | Apply bootstrap + local inbox unread patch |

## Read / notification ownership (intentional open)

When V2 owns the open (`p_mark_read = true` in RPC):

1. `mark_conversation_read` once (in RPC)
2. Conversation-target message notifications marked once (in RPC)
3. Inbox unread patched locally to zero
4. Legacy thread notification effect skipped via `threadBootstrapOwnedReadRef`

When opened from inbox (`consumeConversationOpenFromInbox`), inbox already marked read — thread uses `p_mark_read = false`.

Pagination and soft revalidation never mark read.

## Migration

- `supabase/migrations/20260823120000_rpc_v1_conversation_thread_bootstrap.sql`
- Rollback: `supabase/migrations/rollback/20260823120000_rpc_v1_conversation_thread_bootstrap_rollback.sql`

**Do not apply to production automatically.**

## Validation

```bash
npm run test:backend-v2
node scripts/conversation-thread-rpc-integration.test.mjs   # requires staging creds
node scripts/benchmark-conversation-thread-rpc.mjs
```

## Phase G cleanup — read-state ownership

When `NEXT_PUBLIC_BACKEND_V2_MESSAGE_THREADS=1` and the thread RPC succeeds:

- Intentional open uses `p_mark_read=true` (lifecycle guard prevents Strict Mode duplicates)
- Inbox `openConversation` does **not** call legacy `mark_conversation_read` or global notification PATCH
- Thread notification effect is skipped — RPC `notifications_marked_read` + local cache patch
- Aggregate DM unread patched locally (`messagingInboxLocalPatch`) — no `fetchTotalUnreadMessageCount` fan-out
- Navbar / native tab bar listen for `tj-messaging-dm-unread-local-patch` instead of refetching on thread read

- Trade Rooms, Feed, Stories, `native-ios/`
- Feed/Stories Realtime `user_id=in.(...)` failures (separate phase)
