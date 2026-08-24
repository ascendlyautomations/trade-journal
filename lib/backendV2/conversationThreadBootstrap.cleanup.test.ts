import fs from "node:fs"
import path from "node:path"
import { describe, it, beforeEach } from "node:test"
import { beginThreadOpenLifecycle, resolveThreadBootstrapMarkRead, markThreadReadInFlight, commitThreadMarkRead, clearThreadReadLifecycle, __resetThreadReadLifecycleForTests, } from "./conversationThreadReadLifecycle.ts"
import { messagingBootstrapCacheKey, readMessagingBootstrapCache, writeMessagingBootstrapCache, clearMessagingBootstrapCache, } from "./messagingBootstrapCache.ts"
import { patchMessagingInboxAfterThreadRead, MESSAGING_INBOX_CONVERSATION_UNREAD_PATCH, MESSAGING_DM_UNREAD_LOCAL_PATCH, } from "./messagingInboxLocalPatch.ts"
import { conversationThreadContractFixtures } from "./conversationThreadContractFixtures.ts"
import { decodeConversationThreadBootstrapV1 } from "./conversationThreadContracts.ts"
import { applyConversationThreadBootstrap } from "./conversationThreadBootstrapApply.ts"
import { patchSessionBadges, readSessionBootstrapCache, writeSessionBootstrapCache, clearSessionBootstrapCache } from "./sessionBootstrapCache.ts"
import { sessionFixtures } from "./rpcContractFixtures.ts"
import assert from "node:assert/strict"

type WindowWithDispatch = Pick<Window, "dispatchEvent">

describe("Phase G cleanup — read lifecycle", () => {
  beforeEach(() => {
    __resetThreadReadLifecycleForTests()
  })

  it("intentional cold open resolves markRead=true once", () => {
    const openId = beginThreadOpenLifecycle("u1")
    assert.equal(
      resolveThreadBootstrapMarkRead({
        viewerId: "u1",
        conversationId: "c1",
        openId,
        mode: "intentional-open",
      }),
      true
    )
  })

  it("pagination and revalidation never mark read", () => {
    const openId = beginThreadOpenLifecycle("u1")
    assert.equal(
      resolveThreadBootstrapMarkRead({
        viewerId: "u1",
        conversationId: "c1",
        openId,
        mode: "pagination",
      }),
      false
    )
    assert.equal(
      resolveThreadBootstrapMarkRead({
        viewerId: "u1",
        conversationId: "c1",
        openId,
        mode: "revalidate",
      }),
      false
    )
  })

  it("Strict Mode duplicate resolves to one mark-read decision", () => {
    const openId = beginThreadOpenLifecycle("u1")
    assert.equal(
      resolveThreadBootstrapMarkRead({
        viewerId: "u1",
        conversationId: "c1",
        openId,
        mode: "intentional-open",
      }),
      true
    )
    markThreadReadInFlight("u1", "c1", openId)
    assert.equal(
      resolveThreadBootstrapMarkRead({
        viewerId: "u1",
        conversationId: "c1",
        openId,
        mode: "intentional-open",
      }),
      false
    )
    commitThreadMarkRead("u1", "c1", openId)
    assert.equal(
      resolveThreadBootstrapMarkRead({
        viewerId: "u1",
        conversationId: "c1",
        openId,
        mode: "intentional-open",
      }),
      false
    )
  })

  it("new open lifecycle allows mark read again", () => {
    const openId1 = beginThreadOpenLifecycle("u1")
    commitThreadMarkRead("u1", "c1", openId1)
    const openId2 = beginThreadOpenLifecycle("u1")
    assert.equal(
      resolveThreadBootstrapMarkRead({
        viewerId: "u1",
        conversationId: "c1",
        openId: openId2,
        mode: "intentional-open",
      }),
      true
    )
  })

  it("logout clears lifecycle", () => {
    const openId = beginThreadOpenLifecycle("u1")
    commitThreadMarkRead("u1", "c1", openId)
    clearThreadReadLifecycle("u1")
    const openId2 = beginThreadOpenLifecycle("u1")
    assert.equal(
      resolveThreadBootstrapMarkRead({
        viewerId: "u1",
        conversationId: "c1",
        openId: openId2,
        mode: "intentional-open",
      }),
      true
    )
  })
})

describe("Phase G cleanup — local inbox unread patch", () => {
  beforeEach(() => {
    clearMessagingBootstrapCache()
    clearSessionBootstrapCache()
  })

  it("patches selected conversation unread to zero and aggregate safely", () => {
    writeSessionBootstrapCache("u1", sessionFixtures.freeUser)
    writeMessagingBootstrapCache(
      messagingBootstrapCacheKey({ userId: "u1" }),
      "u1",
      {
        meta: {
          contract_version: "v1",
          server_time: "2026-08-21T12:00:00.000Z",
          viewer_id: "u1",
        },
        data: {
          conversations: [
            {
              id: "c1",
              is_group: false,
              is_pinned: false,
              name: null,
              avatar_url: null,
              last_message: "hi",
              last_message_at: "2026-08-21T12:00:00.000Z",
              unread_count: 3,
              muted: false,
              participants: [],
            },
            {
              id: "c2",
              is_group: false,
              is_pinned: false,
              name: null,
              avatar_url: null,
              last_message: "yo",
              last_message_at: "2026-08-21T11:00:00.000Z",
              unread_count: 2,
              muted: false,
              participants: [],
            },
          ],
          peers: {},
          dm_unread_total: 5,
          muted_ids: [],
          next_cursor: null,
          page_meta: { limit: 40, returned: 2, has_more: false },
        },
      }
    )

    const detail = patchMessagingInboxAfterThreadRead({
      userId: "u1",
      conversationId: "c1",
      previousConversationUnread: 3,
      notificationsMarkedRead: 1,
    })

    assert.equal(detail.unreadCount, 0)
    assert.equal(detail.dmUnreadTotal, 2)

    const cached = readMessagingBootstrapCache(
      messagingBootstrapCacheKey({ userId: "u1" })
    )
    assert.equal(
      cached?.data.conversations.find((c) => c.id === "c1")?.unread_count,
      0
    )
    assert.equal(cached?.data.dm_unread_total, 2)
    assert.equal(readSessionBootstrapCache("u1")?.data.badges.dm_unread, 2)
  })

  it("reapplying patch is idempotent", () => {
    writeMessagingBootstrapCache(
      messagingBootstrapCacheKey({ userId: "u1" }),
      "u1",
      {
        meta: {
          contract_version: "v1",
          server_time: "2026-08-21T12:00:00.000Z",
          viewer_id: "u1",
        },
        data: {
          conversations: [
            {
              id: "c1",
              is_group: false,
              is_pinned: false,
              name: null,
              avatar_url: null,
              last_message: null,
              last_message_at: null,
              unread_count: 0,
              muted: false,
              participants: [],
            },
          ],
          peers: {},
          dm_unread_total: 0,
          muted_ids: [],
          next_cursor: null,
          page_meta: { limit: 40, returned: 1, has_more: false },
        },
      }
    )

    const first = patchMessagingInboxAfterThreadRead({
      userId: "u1",
      conversationId: "c1",
      previousConversationUnread: 0,
    })
    const second = patchMessagingInboxAfterThreadRead({
      userId: "u1",
      conversationId: "c1",
      previousConversationUnread: 0,
    })
    assert.equal(first.dmUnreadTotal, 0)
    assert.equal(second.dmUnreadTotal, 0)
  })

  it("dispatches local inbox + dm unread events", () => {
    const events: string[] = []
    const previousWindow = globalThis.window
    const mockWindow: WindowWithDispatch = {
      dispatchEvent: (event: Event) => {
        events.push(event.type)
        return true
      },
    }
    globalThis.window = mockWindow as Window & typeof globalThis
    try {
      patchMessagingInboxAfterThreadRead({
        userId: "u1",
        conversationId: "c1",
        previousConversationUnread: 1,
      })
    } finally {
      globalThis.window = previousWindow
    }
    assert.ok(events.includes(MESSAGING_INBOX_CONVERSATION_UNREAD_PATCH))
    assert.ok(events.includes(MESSAGING_DM_UNREAD_LOCAL_PATCH))
  })
})

describe("Phase G cleanup — apply bootstrap side effects", () => {
  it("cached apply skips read side effects", () => {
    let messagesSet = false
    const decoded = decodeConversationThreadBootstrapV1(
      JSON.parse(JSON.stringify(conversationThreadContractFixtures.directOpen))
    )
    applyConversationThreadBootstrap(decoded, "viewer-1", "convo-1", {
      setConversation: () => {},
      setParticipants: () => {},
      setOtherUser: () => {},
      setNotificationsEnabled: () => {},
      setDmBlockStatus: () => {},
      setBlockStatusLoading: () => {},
      setMessages: () => {
        messagesSet = true
      },
      setHasOlderMessages: () => {},
      setMessagesLoaded: () => {},
      setMessagesLoadError: () => {},
      conversationMetaRef: { current: null },
      patchConversationSession: () => {},
      urlSegment: "peer",
    }, { skipReadSideEffects: true })

    assert.equal(messagesSet, true)
    assert.equal(
      resolveThreadBootstrapMarkRead({
        viewerId: "viewer-1",
        conversationId: "convo-1",
        openId: beginThreadOpenLifecycle("viewer-1"),
        mode: "intentional-open",
      }),
      true
    )
  })

  it("merges existing messages when applying bootstrap", () => {
    const decoded = decodeConversationThreadBootstrapV1(
      JSON.parse(JSON.stringify(conversationThreadContractFixtures.directOpen))
    )
    let result = []
    applyConversationThreadBootstrap(decoded, "viewer-1", "convo-1", {
      setConversation: () => {},
      setParticipants: () => {},
      setOtherUser: () => {},
      setNotificationsEnabled: () => {},
      setDmBlockStatus: () => {},
      setBlockStatusLoading: () => {},
      setMessages: (m) => {
        result = m
      },
      setHasOlderMessages: () => {},
      setMessagesLoaded: () => {},
      setMessagesLoadError: () => {},
      conversationMetaRef: { current: null },
      patchConversationSession: () => {},
      urlSegment: "peer",
    }, {
      skipReadSideEffects: true,
      existingMessages: [
        {
          id: "msg-2",
          created_at: "2026-08-21T12:00:00.000Z",
          content: "Later",
        },
      ],
    })

    assert.equal(result.length, 2)
  })
})

describe("Phase G cleanup — inbox openConversation gating", () => {
  it("messages page skips legacy mark-read when messageThreads enabled", () => {
    const src = fs.readFileSync(
      path.join(process.cwd(), "app/(app)/messages/page.tsx"),
      "utf8"
    )
    assert.match(src, /isBackendV2Enabled\("messageThreads"\)/)
    assert.match(
      src,
      /if \(isBackendV2Enabled\("messageThreads"\)\) \{\s*return\s*\}/
    )
  })

  it("thread page skips legacy notification effect when messageThreads enabled", () => {
    const src = fs.readFileSync(
      path.join(process.cwd(), "app/messages/[id]/page.tsx"),
      "utf8"
    )
    assert.match(
      src,
      /if \(isBackendV2Enabled\("messageThreads"\)\) return/
    )
  })
})

describe("Phase G cleanup — navbar avoids full unread refetch on local patch", () => {
  it("navbar listens for local dm unread patch event", () => {
    const src = fs.readFileSync(
      path.join(process.cwd(), "app/components/Navbar.tsx"),
      "utf8"
    )
    assert.match(src, /MESSAGING_DM_UNREAD_LOCAL_PATCH/)
    assert.match(
      src,
      /if \(isBackendV2Enabled\("messageThreads"\)\) return/
    )
  })
})
export {}
