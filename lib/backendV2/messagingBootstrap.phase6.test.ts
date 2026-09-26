import { describe, it, beforeEach } from "node:test"
import { messagesBootstrapFixture, } from "./fixtures.ts"
import { compareMessagingBootstraps, } from "./messagingBootstrapCompare.ts"
import { messagingBootstrapCacheKey, readMessagingBootstrapCache, writeMessagingBootstrapCache, clearMessagingBootstrapCache, } from "./messagingBootstrapCache.ts"
import { beginMessagingBootstrapFlight, __resetMessagingBootstrapFlightsForTests, } from "./messagingBootstrapSingleFlight.ts"
import { decodeMessagesBootstrapV1, type MessagesBootstrapV1, } from "./contracts.ts"
import { collectMessagingInboxConversations, } from "./messagingInboxPages.ts"
import { isBackendV2Enabled, resolveBackendV2Flag, __setBackendV2FlagForTests, __resetBackendV2FlagsForTests, } from "./flags.ts"
import { BackendV2RpcNames } from "./versioning.ts"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"

import { fileURLToPath } from "node:url"
const __dirname = path.dirname(fileURLToPath(import.meta.url))

describe("Backend V2 messaging bootstrap (Phase 6)", () => {
  beforeEach(() => {
    clearMessagingBootstrapCache()
    __resetMessagingBootstrapFlightsForTests()
    __resetBackendV2FlagsForTests()
  })

  it("decodes fixture with conversations + dm_unread_total", () => {
    const decoded = decodeMessagesBootstrapV1(
      JSON.parse(JSON.stringify(messagesBootstrapFixture))
    )
    assert.equal(decoded.data.dm_unread_total, 1)
    assert.ok(Array.isArray(decoded.data.conversations))
    assert.equal(decoded.data.page_meta.returned, 1)
  })

  it("messages flag defaults ON and can be rolled back", () => {
    assert.equal(isBackendV2Enabled("messages"), true)
    assert.equal(resolveBackendV2Flag("messages").source, "default")
    assert.equal(isBackendV2Enabled("feed"), true)
    assert.equal(isBackendV2Enabled("session"), false)
    assert.equal(isBackendV2Enabled("dashboard"), false)
    assert.equal(isBackendV2Enabled("profile"), false)
    assert.equal(isBackendV2Enabled("rooms"), false)
    assert.equal(isBackendV2Enabled("propFirm"), false)
    __setBackendV2FlagForTests("messages", false)
    assert.equal(isBackendV2Enabled("messages"), false)
    assert.equal(resolveBackendV2Flag("messages").source, "test")
  })

  it("messages flag accepts MESSAGES or MESSAGING env keys in flags.ts", () => {
    const flagsSrc = fs.readFileSync(
      path.join(__dirname, "flags.ts"),
      "utf8"
    )
    assert.match(flagsSrc, /NEXT_PUBLIC_BACKEND_V2_MESSAGES/)
    assert.match(flagsSrc, /NEXT_PUBLIC_BACKEND_V2_MESSAGING/)
  })

  it("RPC name is rpc_v2_messaging_bootstrap with V1 fallback constant", () => {
    assert.equal(BackendV2RpcNames.messaging, "rpc_v2_messaging_bootstrap")
    assert.equal(BackendV2RpcNames.messagingV1, "rpc_v1_messaging_bootstrap")
  })

  it("compare detects conversation id mismatch", () => {
    const rest = JSON.parse(JSON.stringify(messagesBootstrapFixture))
    const rpc = JSON.parse(JSON.stringify(messagesBootstrapFixture))
    rpc.data.conversations = []
    const mismatches = compareMessagingBootstraps(rest, rpc)
    assert.ok(mismatches.some((m) => m.path === "conversations.ids"))
  })

  it("cache is keyed by user + cursor", () => {
    const uid = messagesBootstrapFixture.meta.viewer_id
    assert.ok(uid)
    const keyA = messagingBootstrapCacheKey({ userId: uid, cursor: null })
    const keyB = messagingBootstrapCacheKey({
      userId: uid,
      cursor: "2026-08-19T19:00:00.000Z",
    })
    writeMessagingBootstrapCache(keyA, uid, messagesBootstrapFixture, "rpc")
    assert.ok(readMessagingBootstrapCache(keyA))
    assert.equal(readMessagingBootstrapCache(keyB), null)
  })

  it("single-flight shares one start", async () => {
    let starts = 0
    const start = async () => {
      starts += 1
      await new Promise((r) => setTimeout(r, 15))
      return { ok: true, starts }
    }
    const [a, b] = await Promise.all([
      beginMessagingBootstrapFlight("k1", "u1", start),
      beginMessagingBootstrapFlight("k1", "u1", start),
    ])
    assert.equal(starts, 1)
    assert.equal(a.starts, 1)
    assert.equal(b.starts, 1)
  })
})

describe("Backend V2 messaging cutover wiring (Phase 6.1)", () => {
  beforeEach(() => {
    __resetBackendV2FlagsForTests()
  })

  it("messages flag OFF is the gate that skips messaging RPC cutover", () => {
    __setBackendV2FlagForTests("messages", false)
    const resolved = resolveBackendV2Flag("messages")
    assert.equal(resolved.enabled, false)
    assert.equal(isBackendV2Enabled("messages"), false)
  })

  it("messages flag ON enables the RPC cutover path", () => {
    __setBackendV2FlagForTests("messages", true)
    assert.equal(isBackendV2Enabled("messages"), true)
    assert.equal(resolveBackendV2Flag("messages").source, "test")
  })

  it("messages page wires fetchConversations through isBackendV2Enabled(messages) before REST", () => {
    const pagePath = path.join(
      __dirname,
      "../../app/(app)/messages/MessagesShell.tsx"
    )
    const src = fs.readFileSync(pagePath, "utf8")
    assert.match(src, /isBackendV2Enabled\("messages"\)/)
    assert.match(src, /loadMessagingBootstrapForUser/)
    assert.match(src, /patchSessionBadges/)
    const rpcLoadIdx = src.indexOf("loadMessagingBootstrapForUser(supabase")
    const restIdx = src.indexOf("fetchUserDmConversations(supabase")
    const unreadIdx = src.indexOf("fetchUnreadCountsForConversations(")
    const muteIdx = src.indexOf("fetchMutedConversationIds(")
    assert.ok(rpcLoadIdx > 0, "expected loadMessagingBootstrapForUser call")
    assert.ok(restIdx > rpcLoadIdx, "REST fan-out must remain after RPC gate")
    assert.ok(unreadIdx > restIdx, "unread query stays on the legacy path")
    assert.ok(muteIdx > restIdx, "mute query stays on the legacy path")
    assert.match(src, /collectMessagingInboxConversations/)
    assert.match(src, /conv\.unread_count/)
  })

  it("repository calls BackendV2RpcNames.messaging via callKnown", () => {
    const repoPath = path.join(__dirname, "messagingBootstrapRepository.ts")
    const src = fs.readFileSync(repoPath, "utf8")
    assert.match(src, /BackendV2RpcNames\.messaging/)
    assert.match(src, /BackendV2RpcNames\.messagingV1/)
    assert.match(src, /isMessagingV2Unavailable/)
  })
})

describe("Messages inbox adoption", () => {
  beforeEach(() => {
    clearMessagingBootstrapCache()
    __resetBackendV2FlagsForTests()
  })

  function page(
    conversations: MessagesBootstrapV1["data"]["conversations"],
    nextCursor: string | null,
    hasMore: boolean
  ): MessagesBootstrapV1 {
    return {
      ...messagesBootstrapFixture,
      data: {
        ...messagesBootstrapFixture.data,
        conversations,
        next_cursor: nextCursor,
        page_meta: {
          limit: 80,
          returned: conversations.length,
          has_more: hasMore,
        },
      },
    }
  }

  it("NEXT_PUBLIC_BACKEND_V2_MESSAGES=0 rolls messages back and leaves other flags", () => {
    const prev = process.env.NEXT_PUBLIC_BACKEND_V2_MESSAGES
    process.env.NEXT_PUBLIC_BACKEND_V2_MESSAGES = "0"
    try {
      assert.equal(isBackendV2Enabled("messages"), false)
      assert.equal(resolveBackendV2Flag("messages").source, "env")
      assert.equal(isBackendV2Enabled("feed"), true)
      assert.equal(isBackendV2Enabled("session"), false)
      assert.equal(isBackendV2Enabled("dashboard"), false)
      assert.equal(isBackendV2Enabled("profile"), false)
      assert.equal(isBackendV2Enabled("rooms"), false)
      assert.equal(isBackendV2Enabled("propFirm"), false)
    } finally {
      if (prev === undefined) delete process.env.NEXT_PUBLIC_BACKEND_V2_MESSAGES
      else process.env.NEXT_PUBLIC_BACKEND_V2_MESSAGES = prev
    }
  })

  it("clearing one user leaves another user's inbox cache", () => {
    const a = messagingBootstrapCacheKey({ userId: "user-a", cursor: null })
    const b = messagingBootstrapCacheKey({ userId: "user-b", cursor: null })
    writeMessagingBootstrapCache(a, "user-a", messagesBootstrapFixture, "rpc")
    writeMessagingBootstrapCache(b, "user-b", messagesBootstrapFixture, "rpc")
    clearMessagingBootstrapCache("user-a")
    assert.equal(readMessagingBootstrapCache(a), null)
    assert.ok(readMessagingBootstrapCache(b))
  })

  it("collects later inbox pages without duplicating a conversation", async () => {
    const firstRow = messagesBootstrapFixture.data.conversations[0]!
    const second = {
      ...firstRow,
      id: "c2222222-2222-2222-2222-222222222222",
      is_group: true,
      name: "Desk",
      last_message: null,
      last_message_at: null,
      unread_count: 0,
      muted: true,
    }
    const calls: string[] = []
    const rows = await collectMessagingInboxConversations(
      page([firstRow], "2026-08-19T19:00:00.000Z|c1", true),
      async (cursor) => {
        calls.push(cursor)
        return page([firstRow, second], null, false)
      }
    )
    assert.deepEqual(calls, ["2026-08-19T19:00:00.000Z|c1"])
    assert.deepEqual(
      rows.map((row) => row.id),
      [firstRow.id, second.id]
    )
    assert.equal(rows[1]?.muted, true)
    assert.equal(rows[1]?.unread_count, 0)
    assert.equal(rows[1]?.last_message, null)
  })

  it("stops when the cursor does not advance", async () => {
    const firstRow = messagesBootstrapFixture.data.conversations[0]!
    let calls = 0
    const rows = await collectMessagingInboxConversations(
      page([firstRow], "same-cursor", true),
      async () => {
        calls += 1
        return page([firstRow], "same-cursor", true)
      }
    )
    assert.equal(calls, 1)
    assert.equal(rows.length, 1)
  })

  it("does not request another page when the caller cancels", async () => {
    const firstRow = messagesBootstrapFixture.data.conversations[0]!
    let calls = 0
    const rows = await collectMessagingInboxConversations(
      page([firstRow], "cursor", true),
      async () => {
        calls += 1
        return page([], null, false)
      },
      () => false
    )
    assert.equal(calls, 0)
    assert.equal(rows.length, 1)
  })

  it("canonical inbox order is pinned, then latest message, then message id", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/20260826210000_rpc_v2_messaging_bootstrap_canonical_messages.sql"
      ),
      "utf8"
    )
    assert.match(sql, /coalesce\(c\.is_pinned, false\) desc/)
    assert.match(sql, /lm\.created_at desc nulls last/)
    assert.match(sql, /lm\.message_id desc nulls last/)
    assert.match(sql, /c\.id desc/)
    assert.match(sql, /then 0/)
    assert.match(sql, /get_conversation_unread_counts/)
    assert.match(sql, /get_hidden_blocked_dm_conversation_ids/)
    assert.match(sql, /notifications_enabled = false/)
  })
})
export {}
