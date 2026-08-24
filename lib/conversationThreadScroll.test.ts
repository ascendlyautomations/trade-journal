import { describe, it, beforeEach } from "node:test"
import { beginThreadScrollOpen, captureThreadPaginationAnchor, createThreadScrollSession, getThreadScrollSession, isThreadNearBottom, isThreadScrollRevealReady, requestThreadJumpToNewest, requestThreadLocalSendScroll, restoreThreadPaginationAnchor, runThreadScrollLayoutPass, shouldPinThreadOnKeyboard, updateThreadPinnedBottomIntent, __resetThreadScrollSessionsForTests, } from "./conversationThreadScroll.ts"
import assert from "node:assert/strict"

function mockContainer(input: {
  scrollTop?: number
  scrollHeight?: number
  clientHeight?: number
  messages?: Array<{ id: string; top: number; height: number }>
}) {
  const scrollTop = input.scrollTop ?? 0
  let currentTop = scrollTop
  let scrollHeight = input.scrollHeight ?? 1000
  const clientHeight = input.clientHeight ?? 400
  const containerTop = 100

  const el = {
    clientHeight,
    scrollTo({ top, behavior }: { top: number; behavior?: string }) {
      currentTop = top
    },
    getBoundingClientRect() {
      return {
        top: containerTop,
        bottom: containerTop + clientHeight,
        height: clientHeight,
      }
    },
    querySelector(selector: string) {
      const match = selector.match(/data-dm-message-id="([^"]+)"/)
      const id = match?.[1]
      const row = input.messages?.find((m) => m.id === id)
      if (!row) return null
      return {
        getBoundingClientRect() {
          return {
            top: containerTop + row.top - currentTop,
            bottom: containerTop + row.top - currentTop + row.height,
            height: row.height,
          }
        },
        getAttribute(name: string) {
          return name === "data-dm-message-id" ? id : null
        },
      }
    },
    querySelectorAll(selector: string) {
      if (!selector.includes("data-dm-message-id")) return []
      return (input.messages ?? []).map((row) => ({
        getAttribute(name: string) {
          return name === "data-dm-message-id" ? row.id : null
        },
        getBoundingClientRect() {
          return {
            top: containerTop + row.top - currentTop,
            bottom: containerTop + row.top - currentTop + row.height,
            height: row.height,
          }
        },
      }))
    },
  }

  Object.defineProperty(el, "scrollTop", {
    configurable: true,
    get() {
      return currentTop
    },
    set(value) {
      currentTop = value
    },
  })

  Object.defineProperty(el, "scrollHeight", {
    configurable: true,
    get() {
      return scrollHeight
    },
    set(value) {
      scrollHeight = value
    },
  })

  return el as unknown as HTMLElement
}

type MockScrollContainer = HTMLElement & {
  scrollHeight: number
}

function setMockScrollHeight(container: HTMLElement, height: number) {
  ;(container as MockScrollContainer).scrollHeight = height
}

describe("conversationThreadScroll — initial open", () => {
  beforeEach(() => {
    __resetThreadScrollSessionsForTests()
  })

  it("cold conversation opens at bottom once", () => {
    const session = createThreadScrollSession()
    beginThreadScrollOpen(session, "u1", "c1", 1)
    const container = mockContainer({ scrollHeight: 800, clientHeight: 400 })

    const first = runThreadScrollLayoutPass({
      session,
      container,
      messagesLoaded: true,
      newestMessageId: "m1",
      previewsReady: false,
      lastMessageInDom: true,
    })

    assert.equal(first.scrolled, true)
    assert.equal(session.phase, "stabilizing")
    assert.equal(isThreadScrollRevealReady(session), false)

    const second = runThreadScrollLayoutPass({
      session,
      container,
      messagesLoaded: true,
      newestMessageId: "m1",
      previewsReady: true,
      lastMessageInDom: true,
    })
    assert.equal(second.scrolled, true)

    const third = runThreadScrollLayoutPass({
      session,
      container,
      messagesLoaded: true,
      newestMessageId: "m1",
      previewsReady: true,
      lastMessageInDom: true,
    })
    assert.equal(third.revealReady, true)
    assert.equal(session.phase, "committed")
    assert.equal(isThreadNearBottom(container), true)
  })

  it("conversation A → B resets initial scroll for B", () => {
    const sessionA = getThreadScrollSession("u1", "a")
    beginThreadScrollOpen(sessionA, "u1", "a", 1)
    const sessionB = getThreadScrollSession("u1", "b")
    beginThreadScrollOpen(sessionB, "u1", "b", 2)
    assert.equal(sessionB.phase, "pending")
    assert.equal(sessionB.openToken, 2)
  })

  it("Strict Mode duplicate layout does not restart committed open", () => {
    const session = createThreadScrollSession()
    beginThreadScrollOpen(session, "u1", "c1", 1)
    session.phase = "committed"
    session.lastSeenNewestMessageId = "m1"

    beginThreadScrollOpen(session, "u1", "c1", 1)
    assert.equal(session.phase, "committed")
  })
})

describe("conversationThreadScroll — pagination anchor", () => {
  it("captures and restores visible anchor", () => {
    const container = mockContainer({
      scrollTop: 120,
      scrollHeight: 1200,
      clientHeight: 400,
      messages: [
        { id: "m-old", top: 20, height: 40 },
        { id: "m-visible", top: 140, height: 40 },
      ],
    })

    const anchor = captureThreadPaginationAnchor(container)
    assert.ok(anchor)
    assert.equal(anchor.messageId, "m-visible")

    container.scrollTop = 320
    assert.equal(restoreThreadPaginationAnchor(container, anchor!), true)
    assert.ok(container.scrollTop < 320)
  })
})

describe("conversationThreadScroll — realtime and send", () => {
  beforeEach(() => {
    __resetThreadScrollSessionsForTests()
  })

  it("remote message while at bottom stays pinned", () => {
    const session = createThreadScrollSession()
    beginThreadScrollOpen(session, "u1", "c1", 1)
    session.phase = "committed"
    session.lastSeenNewestMessageId = "m1"
    session.pinnedBottomIntent = true

    const container = mockContainer({ scrollHeight: 800, clientHeight: 400 })
    container.scrollTop = 400

    const result = runThreadScrollLayoutPass({
      session,
      container,
      messagesLoaded: true,
      newestMessageId: "m2",
      previewsReady: true,
      lastMessageInDom: true,
    })

    assert.equal(result.scrolled, true)
    assert.equal(session.newMessagesBelow, 0)
  })

  it("remote message while scrolled up preserves position", () => {
    const session = createThreadScrollSession()
    session.phase = "committed"
    session.lastSeenNewestMessageId = "m1"
    session.pinnedBottomIntent = false

    const container = mockContainer({ scrollTop: 10, scrollHeight: 1200, clientHeight: 400 })

    runThreadScrollLayoutPass({
      session,
      container,
      messagesLoaded: true,
      newestMessageId: "m2",
      previewsReady: true,
      lastMessageInDom: true,
    })

    assert.equal(session.newMessagesBelow, 1)
    assert.equal(container.scrollTop, 10)
  })

  it("local send requests one bottom scroll", () => {
    const session = createThreadScrollSession()
    session.phase = "committed"
    requestThreadLocalSendScroll(session)
    assert.equal(session.pendingLocalSendScroll, true)

    const container = mockContainer({ scrollHeight: 900, clientHeight: 400 })
    runThreadScrollLayoutPass({
      session,
      container,
      messagesLoaded: true,
      newestMessageId: "m3",
      previewsReady: true,
      lastMessageInDom: true,
    })

    assert.equal(session.pendingLocalSendScroll, false)
    assert.equal(isThreadNearBottom(container), true)
  })

  it("jump to newest clears new message counter", () => {
    const session = createThreadScrollSession()
    session.phase = "committed"
    session.newMessagesBelow = 2
    updateThreadPinnedBottomIntent(session, false)
    requestThreadJumpToNewest(session)
    assert.equal(session.newMessagesBelow, 0)
    assert.equal(session.pendingLocalSendScroll, true)
  })

  it("realtime echo does not queue another local send scroll", () => {
    const session = createThreadScrollSession()
    session.phase = "committed"
    session.lastSeenNewestMessageId = "temp-1"
    session.pinnedBottomIntent = true

    requestThreadLocalSendScroll(session)
    const container = mockContainer({ scrollHeight: 900, clientHeight: 400 })

    runThreadScrollLayoutPass({
      session,
      container,
      messagesLoaded: true,
      newestMessageId: "temp-1",
      previewsReady: true,
      lastMessageInDom: true,
    })
    assert.equal(session.pendingLocalSendScroll, false)

    runThreadScrollLayoutPass({
      session,
      container,
      messagesLoaded: true,
      newestMessageId: "real-1",
      previewsReady: true,
      lastMessageInDom: true,
    })
    assert.equal(session.pendingLocalSendScroll, false)
    assert.equal(session.newMessagesBelow, 0)
  })
})

describe("conversationThreadScroll — conversation identity", () => {
  beforeEach(() => {
    __resetThreadScrollSessionsForTests()
  })

  it("cached conversation uses same initial open lifecycle as cold", () => {
    const session = getThreadScrollSession("u1", "cached-convo")
    beginThreadScrollOpen(session, "u1", "cached-convo", 1)
    assert.equal(session.phase, "pending")

    const container = mockContainer({ scrollHeight: 600, clientHeight: 400 })
    runThreadScrollLayoutPass({
      session,
      container,
      messagesLoaded: true,
      newestMessageId: "m-last",
      previewsReady: false,
      lastMessageInDom: true,
    })
    assert.equal(session.phase, "stabilizing")
  })

  it("alias resolution reuses one open token without restarting committed scroll", () => {
    const session = getThreadScrollSession("u1", "resolved-id")
    beginThreadScrollOpen(session, "u1", "resolved-id", 3)
    session.phase = "committed"
    session.lastSeenNewestMessageId = "m1"

    beginThreadScrollOpen(session, "u1", "resolved-id", 3)
    assert.equal(session.phase, "committed")
  })

  it("late conversation A response cannot scroll conversation B", () => {
    const sessionA = getThreadScrollSession("u1", "a")
    beginThreadScrollOpen(sessionA, "u1", "a", 1)
    sessionA.phase = "committed"
    sessionA.lastSeenNewestMessageId = "a-old"

    const sessionB = getThreadScrollSession("u1", "b")
    beginThreadScrollOpen(sessionB, "u1", "b", 2)
    const containerB = mockContainer({ scrollHeight: 700, clientHeight: 400 })

    runThreadScrollLayoutPass({
      session: sessionB,
      container: containerB,
      messagesLoaded: true,
      newestMessageId: "b-new",
      previewsReady: false,
      lastMessageInDom: true,
    })

    const containerA = mockContainer({ scrollTop: 50, scrollHeight: 900, clientHeight: 400 })
    sessionA.pinnedBottomIntent = false
    runThreadScrollLayoutPass({
      session: sessionA,
      container: containerA,
      messagesLoaded: true,
      newestMessageId: "a-late",
      previewsReady: true,
      lastMessageInDom: true,
    })

    assert.equal(sessionB.phase, "stabilizing")
    assert.equal(containerA.scrollTop, 50)
  })
})

describe("conversationThreadScroll — edge cases", () => {
  beforeEach(() => {
    __resetThreadScrollSessionsForTests()
  })

  it("empty conversation remains stable at bottom", () => {
    const session = createThreadScrollSession()
    beginThreadScrollOpen(session, "u1", "empty", 1)
    const container = mockContainer({ scrollHeight: 400, clientHeight: 400 })

    const result = runThreadScrollLayoutPass({
      session,
      container,
      messagesLoaded: true,
      newestMessageId: null,
      previewsReady: true,
      lastMessageInDom: false,
    })

    assert.equal(result.revealReady, true)
    assert.equal(session.phase, "committed")
    assert.equal(isThreadNearBottom(container), true)
  })

  it("one-message conversation remains stable", () => {
    const session = createThreadScrollSession()
    beginThreadScrollOpen(session, "u1", "solo", 1)
    const container = mockContainer({ scrollHeight: 500, clientHeight: 400 })

    runThreadScrollLayoutPass({
      session,
      container,
      messagesLoaded: true,
      newestMessageId: "only",
      previewsReady: true,
      lastMessageInDom: true,
    })
    runThreadScrollLayoutPass({
      session,
      container,
      messagesLoaded: true,
      newestMessageId: "only",
      previewsReady: true,
      lastMessageInDom: true,
    })
    runThreadScrollLayoutPass({
      session,
      container,
      messagesLoaded: true,
      newestMessageId: "only",
      previewsReady: true,
      lastMessageInDom: true,
    })

    assert.equal(session.phase, "committed")
    assert.equal(isThreadNearBottom(container), true)
  })

  it("image height growth preserves bottom only when pinned", () => {
    const session = createThreadScrollSession()
    session.phase = "committed"
    session.pinnedBottomIntent = true
    session.lastSeenNewestMessageId = "m1"
    session.lastScrollHeight = 800

    const container = mockContainer({ scrollHeight: 800, clientHeight: 400 })
    container.scrollTop = 400

    setMockScrollHeight(container, 980)
    runThreadScrollLayoutPass({
      session,
      container,
      messagesLoaded: true,
      newestMessageId: "m1",
      previewsReady: true,
      lastMessageInDom: true,
    })
    assert.equal(isThreadNearBottom(container), true)

    session.pinnedBottomIntent = false
    container.scrollTop = 40
    setMockScrollHeight(container, 1100)
    const before = container.scrollTop
    runThreadScrollLayoutPass({
      session,
      container,
      messagesLoaded: true,
      newestMessageId: "m1",
      previewsReady: true,
      lastMessageInDom: true,
    })
    assert.equal(container.scrollTop, before)
  })

  it("keyboard pin applies only when viewer was already at bottom", () => {
    const session = createThreadScrollSession()
    session.phase = "stabilizing"
    session.pinnedBottomIntent = true
    assert.equal(shouldPinThreadOnKeyboard(session), false)

    session.phase = "committed"
    assert.equal(shouldPinThreadOnKeyboard(session), true)

    session.pinnedBottomIntent = false
    assert.equal(shouldPinThreadOnKeyboard(session), false)
  })
})
export {}
