export function sortMessagesByCreatedAt(messages: any[]): any[] {
  return [...messages].sort(
    (a, b) =>
      new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
  )
}

export function filterMessagesForUser(
  messages: any[],
  deletedMessageIds: Set<string>
): any[] {
  return messages.filter((msg) => {
    if (msg.deleted_for_everyone) return true
    return !deletedMessageIds.has(String(msg.id))
  })
}

export function mergeMessageLists(existing: any[], incoming: any[]): any[] {
  const byId = new Map<string, any>()
  for (const msg of existing) {
    byId.set(String(msg.id), msg)
  }
  for (const msg of incoming) {
    const id = String(msg.id)
    const prev = byId.get(id)
    byId.set(
      id,
      prev
        ? { ...prev, ...msg, profiles: msg.profiles ?? prev.profiles }
        : msg
    )
  }
  return sortMessagesByCreatedAt([...byId.values()])
}

export function computeNewestMessage(messages: any[]): {
  id: string | null
  timestamp: string | null
} {
  let newest: any = null
  for (const message of messages) {
    if (!message?.created_at) continue
    if (
      !newest ||
      new Date(message.created_at).getTime() >
        new Date(newest.created_at).getTime()
    ) {
      newest = message
    }
  }
  if (!newest) return { id: null, timestamp: null }
  return {
    id: String(newest.id),
    timestamp: String(newest.created_at),
  }
}

export function isScrollNearBottom(
  scrollTop: number,
  scrollHeight: number,
  clientHeight: number,
  threshold = 80
): boolean {
  return scrollHeight - scrollTop - clientHeight < threshold
}

/** True when shared trade/post previews needed by the list are in cache. */
export function areConversationPreviewsReady(
  messages: any[],
  tradesById: Record<string, any>,
  postsById: Record<string, any>,
  tradeKey: (tradeId: string) => string | null,
  postKey: (message: any) => string | null
): boolean {
  for (const msg of messages) {
    if (msg.type === "trade" && msg.trade_id) {
      const key = tradeKey(String(msg.trade_id))
      if (key && !tradesById[key]) return false
    }
    const key = postKey(msg)
    if (key && !postsById[key]) return false
  }
  return true
}
