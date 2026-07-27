type MessagingActiveContext = {
  conversationId: string | null
  roomId: string | null
  roomSlug: string | null
}

let active: MessagingActiveContext = {
  conversationId: null,
  roomId: null,
  roomSlug: null,
}

const listeners = new Set<() => void>()

function notify() {
  for (const listener of listeners) {
    try {
      listener()
    } catch {
      /* ignore */
    }
  }
}

export function getMessagingActiveContext(): MessagingActiveContext {
  return { ...active }
}

export function setActiveConversationId(conversationId: string | null) {
  const next = conversationId?.trim() || null
  if (active.conversationId === next) return
  active = { ...active, conversationId: next }
  notify()
}

export function setActiveRoomContext(opts: {
  roomId?: string | null
  roomSlug?: string | null
} | null) {
  const roomId = opts?.roomId?.trim() || null
  const roomSlug = opts?.roomSlug?.trim() || null
  if (active.roomId === roomId && active.roomSlug === roomSlug) return
  active = { ...active, roomId, roomSlug }
  notify()
}

export function isViewingConversation(conversationId: string | null | undefined): boolean {
  const id = conversationId?.trim()
  if (!id) return false
  return active.conversationId === id
}

export function isViewingRoom(opts: {
  roomId?: string | null
  roomSlug?: string | null
}): boolean {
  const roomId = opts.roomId?.trim()
  const roomSlug = opts.roomSlug?.trim()
  if (roomId && active.roomId === roomId) return true
  if (roomSlug && active.roomSlug === roomSlug) return true
  return false
}

/** Whether the user is already looking at the destination this push targets. */
export function isViewingMessagingTarget(href: string | null | undefined): boolean {
  if (!href?.startsWith("/")) return false
  try {
    const url = new URL(href, "https://tradetrax.local")
    if (url.pathname.startsWith("/messages/")) {
      const segment = url.pathname.slice("/messages/".length).split("/")[0] ?? ""
      return Boolean(segment && active.conversationId === segment)
    }
    if (url.pathname === "/community" || url.pathname.startsWith("/community")) {
      const room = url.searchParams.get("room")?.trim()
      if (!room) return false
      return (
        (active.roomSlug != null && active.roomSlug === room) ||
        (active.roomId != null && active.roomId === room)
      )
    }
    return false
  } catch {
    return false
  }
}

export function subscribeMessagingActiveContext(listener: () => void): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

export const MESSAGING_IN_APP_BANNER_EVENT = "tj-messaging-in-app-banner"

export type MessagingInAppBannerDetail = {
  title: string
  body: string
  href: string
  conversationId?: string | null
  roomId?: string | null
  roomSlug?: string | null
  notificationType?: string | null
}

export function dispatchMessagingInAppBanner(detail: MessagingInAppBannerDetail) {
  if (typeof window === "undefined") return
  if (detail.conversationId && isViewingConversation(detail.conversationId)) return
  if (isViewingRoom({ roomId: detail.roomId, roomSlug: detail.roomSlug })) {
    return
  }
  if (
    !detail.conversationId &&
    !detail.roomId &&
    !detail.roomSlug &&
    isViewingMessagingTarget(detail.href)
  ) {
    return
  }
  window.dispatchEvent(
    new CustomEvent(MESSAGING_IN_APP_BANNER_EVENT, { detail })
  )
}
