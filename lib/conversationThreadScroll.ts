import { isScrollNearBottom } from "./conversationMessageUtils.ts"
import { scrollContainerToBottom } from "./conversationScroll.ts"

export const THREAD_SCROLL_NEAR_BOTTOM_THRESHOLD_PX = 80

export type ThreadScrollPhase = "idle" | "pending" | "stabilizing" | "committed"

export type ThreadPaginationAnchor = {
  messageId: string
  offsetPx: number
}

export type ThreadScrollSession = {
  viewerId: string | null
  conversationId: string | null
  openToken: number
  phase: ThreadScrollPhase
  stableHeightFrames: number
  lastScrollHeight: number
  pinnedBottomIntent: boolean
  pendingLocalSendScroll: boolean
  newMessagesBelow: number
  lastSeenNewestMessageId: string | null
}

const sessions = new Map<string, ThreadScrollSession>()

function sessionKey(viewerId: string, conversationId: string): string {
  return `${viewerId.trim()}|${conversationId.trim()}`
}

export function createThreadScrollSession(): ThreadScrollSession {
  return {
    viewerId: null,
    conversationId: null,
    openToken: 0,
    phase: "idle",
    stableHeightFrames: 0,
    lastScrollHeight: 0,
    pinnedBottomIntent: true,
    pendingLocalSendScroll: false,
    newMessagesBelow: 0,
    lastSeenNewestMessageId: null,
  }
}

export function getThreadScrollSession(
  viewerId: string,
  conversationId: string
): ThreadScrollSession {
  const key = sessionKey(viewerId, conversationId)
  let session = sessions.get(key)
  if (!session) {
    session = createThreadScrollSession()
    sessions.set(key, session)
  }
  return session
}

export function clearThreadScrollSessions(viewerId?: string | null): void {
  if (!viewerId) {
    sessions.clear()
    return
  }
  const prefix = `${viewerId.trim()}|`
  for (const key of sessions.keys()) {
    if (key.startsWith(prefix)) sessions.delete(key)
  }
}

export function beginThreadScrollOpen(
  session: ThreadScrollSession,
  viewerId: string,
  conversationId: string,
  openToken: number
): void {
  const changed =
    session.viewerId !== viewerId ||
    session.conversationId !== conversationId ||
    session.openToken !== openToken

  if (!changed) return

  session.viewerId = viewerId
  session.conversationId = conversationId
  session.openToken = openToken
  session.phase = "pending"
  session.stableHeightFrames = 0
  session.lastScrollHeight = 0
  session.pinnedBottomIntent = true
  session.pendingLocalSendScroll = false
  session.newMessagesBelow = 0
  session.lastSeenNewestMessageId = null
}

export function isThreadScrollRevealReady(session: ThreadScrollSession): boolean {
  return session.phase === "committed" || session.phase === "idle"
}

export function isThreadNearBottom(
  container: HTMLElement,
  threshold = THREAD_SCROLL_NEAR_BOTTOM_THRESHOLD_PX
): boolean {
  return isScrollNearBottom(
    container.scrollTop,
    container.scrollHeight,
    container.clientHeight,
    threshold
  )
}

export function scrollThreadContainerToBottom(
  container: HTMLElement,
  behavior: ScrollBehavior = "auto"
): void {
  scrollContainerToBottom(container, { behavior })
}

export function captureThreadPaginationAnchor(
  container: HTMLElement
): ThreadPaginationAnchor | null {
  const nodes = container.querySelectorAll<HTMLElement>("[data-dm-message-id]")
  const containerTop = container.getBoundingClientRect().top
  for (const node of nodes) {
    const rect = node.getBoundingClientRect()
    if (rect.bottom <= containerTop + 1) continue
    const messageId = node.getAttribute("data-dm-message-id")
    if (!messageId) continue
    return {
      messageId,
      offsetPx: rect.top - containerTop,
    }
  }
  return null
}

export function restoreThreadPaginationAnchor(
  container: HTMLElement,
  anchor: ThreadPaginationAnchor
): boolean {
  const escapedId =
    typeof CSS !== "undefined" && typeof CSS.escape === "function"
      ? CSS.escape(anchor.messageId)
      : anchor.messageId.replace(/\\/g, "\\\\").replace(/"/g, '\\"')
  const node = container.querySelector<HTMLElement>(
    `[data-dm-message-id="${escapedId}"]`
  )
  if (!node) return false
  const containerTop = container.getBoundingClientRect().top
  const rect = node.getBoundingClientRect()
  const delta = rect.top - containerTop - anchor.offsetPx
  if (Math.abs(delta) < 0.5) return true
  container.scrollTop += delta
  return true
}

export type ThreadScrollLayoutInput = {
  session: ThreadScrollSession
  container: HTMLElement
  messagesLoaded: boolean
  newestMessageId: string | null
  previewsReady: boolean
  lastMessageInDom: boolean
  prefersReducedMotion?: boolean
}

export type ThreadScrollLayoutResult = {
  revealReady: boolean
  scrolled: boolean
}

/** One layout pass for initial open, local send, and bottom-pinned realtime. */
export function runThreadScrollLayoutPass(
  input: ThreadScrollLayoutInput
): ThreadScrollLayoutResult {
  const { session, container, messagesLoaded, newestMessageId } = input
  let scrolled = false

  if (!messagesLoaded) {
    return { revealReady: isThreadScrollRevealReady(session), scrolled }
  }

  if (session.phase === "pending") {
    scrollThreadContainerToBottom(container, "auto")
    session.phase = "stabilizing"
    session.stableHeightFrames = 0
    session.lastScrollHeight = container.scrollHeight
    session.pinnedBottomIntent = true
    session.lastSeenNewestMessageId = newestMessageId
    scrolled = true
  }

  if (session.pendingLocalSendScroll) {
    const behavior: ScrollBehavior = input.prefersReducedMotion ? "auto" : "smooth"
    scrollThreadContainerToBottom(container, behavior)
    session.pendingLocalSendScroll = false
    session.pinnedBottomIntent = true
    session.newMessagesBelow = 0
    session.lastSeenNewestMessageId = newestMessageId
    scrolled = true
  }

  if (
    session.phase === "stabilizing" &&
    session.pinnedBottomIntent &&
    !session.pendingLocalSendScroll
  ) {
    scrollThreadContainerToBottom(container, "auto")
    scrolled = true

    const height = container.scrollHeight
    const atBottom = isThreadNearBottom(container)
    if (height === session.lastScrollHeight && atBottom) {
      session.stableHeightFrames += 1
    } else {
      session.stableHeightFrames = 0
      session.lastScrollHeight = height
    }

    const stableEnough =
      session.stableHeightFrames >= 2 ||
      (atBottom &&
        input.previewsReady &&
        input.lastMessageInDom &&
        newestMessageId != null)

    if (stableEnough || !newestMessageId) {
      session.phase = "committed"
      session.lastSeenNewestMessageId = newestMessageId
    }
  }

  if (session.phase === "committed" && newestMessageId) {
    const newestChanged =
      session.lastSeenNewestMessageId != null &&
      newestMessageId !== session.lastSeenNewestMessageId

    if (newestChanged) {
      if (session.pinnedBottomIntent && isThreadNearBottom(container)) {
        scrollThreadContainerToBottom(container, "auto")
        session.newMessagesBelow = 0
        scrolled = true
      } else if (!session.pinnedBottomIntent || !isThreadNearBottom(container)) {
        session.newMessagesBelow += 1
      }
      session.lastSeenNewestMessageId = newestMessageId
    } else if (session.pinnedBottomIntent) {
      const height = container.scrollHeight
      if (height !== session.lastScrollHeight) {
        scrollThreadContainerToBottom(container, "auto")
        session.lastScrollHeight = height
        scrolled = true
      }
    }
  }

  return {
    revealReady: isThreadScrollRevealReady(session),
    scrolled,
  }
}

export function requestThreadLocalSendScroll(session: ThreadScrollSession): void {
  session.pendingLocalSendScroll = true
  session.pinnedBottomIntent = true
  session.newMessagesBelow = 0
}

export function requestThreadJumpToNewest(session: ThreadScrollSession): void {
  session.pinnedBottomIntent = true
  session.newMessagesBelow = 0
  session.pendingLocalSendScroll = true
}

export function updateThreadPinnedBottomIntent(
  session: ThreadScrollSession,
  nearBottom: boolean
): void {
  session.pinnedBottomIntent = nearBottom
  if (nearBottom) {
    session.newMessagesBelow = 0
  }
}

export function shouldPinThreadOnKeyboard(session: ThreadScrollSession): boolean {
  return session.phase === "committed" && session.pinnedBottomIntent
}

/** @internal */
export function __resetThreadScrollSessionsForTests(): void {
  sessions.clear()
}
