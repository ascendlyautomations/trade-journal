/** Inbox open intent — scroll to newest + known conversation id for fast thread open. */

const OPEN_PREFIX = "tj-dm-open-from-inbox:"
const CONVERSATION_ID_PREFIX = "tj-dm-inbox-conversation:"

function normalizeUrlSegment(urlSegment: string): string {
  return urlSegment.trim().toLowerCase()
}

export function markConversationOpenFromInbox(
  conversationId: string,
  urlSegment: string
) {
  if (typeof sessionStorage === "undefined") return
  const segment = normalizeUrlSegment(urlSegment)
  sessionStorage.setItem(`${OPEN_PREFIX}${conversationId}`, String(Date.now()))
  if (segment) {
    sessionStorage.setItem(`${CONVERSATION_ID_PREFIX}${segment}`, conversationId)
  }
}

export function consumeConversationOpenFromInbox(conversationId: string): boolean {
  if (typeof sessionStorage === "undefined") return false
  const key = `${OPEN_PREFIX}${conversationId}`
  const had = sessionStorage.getItem(key) !== null
  sessionStorage.removeItem(key)
  return had
}

/** Returns inbox-known conversation id for a thread URL segment (consumes entry). */
export function consumeInboxConversationId(urlSegment: string): string | null {
  if (typeof sessionStorage === "undefined") return null
  const key = `${CONVERSATION_ID_PREFIX}${normalizeUrlSegment(urlSegment)}`
  const id = sessionStorage.getItem(key)
  sessionStorage.removeItem(key)
  return id?.trim() || null
}

/** Peek without consuming — used to detect cache fast-path before navigation completes. */
export function peekInboxConversationId(urlSegment: string): string | null {
  if (typeof sessionStorage === "undefined") return null
  const key = `${CONVERSATION_ID_PREFIX}${normalizeUrlSegment(urlSegment)}`
  return sessionStorage.getItem(key)?.trim() || null
}
