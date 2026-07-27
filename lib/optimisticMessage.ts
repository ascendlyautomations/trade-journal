/**
 * Helpers for optimistic outbound messages + realtime dedupe.
 */

export type MessageSendStatus = "sending" | "sent" | "failed"

export const CLIENT_TEMP_ID_KEY = "client_temp_id"
export const SEND_STATUS_KEY = "send_status"

export function isOptimisticMessageId(id: unknown): boolean {
  return typeof id === "string" && id.startsWith("temp-")
}

export function mergeRealtimeMessageIntoList<
  T extends {
    id?: unknown
    sender_id?: unknown
    content?: unknown
    created_at?: unknown
    client_temp_id?: unknown
    send_status?: unknown
  },
>(prev: T[], incoming: T, currentUserId?: string | null): T[] {
  const incomingId = String(incoming.id ?? "")
  if (!incomingId) return prev

  if (prev.some((m) => String(m.id) === incomingId)) {
    return prev.map((m) =>
      String(m.id) === incomingId ? { ...m, ...incoming, send_status: "sent" } : m
    )
  }

  // Replace optimistic outbound bubble when realtime/server confirms.
  const incomingContent = String(incoming.content ?? "")
  const incomingSender = String(incoming.sender_id ?? "")
  const incomingCreated = new Date(String(incoming.created_at ?? "")).getTime()

  const tempIndex = prev.findIndex((m) => {
    if (!isOptimisticMessageId(m.id)) return false
    if (currentUserId && String(m.sender_id) !== currentUserId) return false
    if (incomingSender && String(m.sender_id) !== incomingSender) return false
    const sameContent = String(m.content ?? "") === incomingContent
    if (!sameContent && incomingContent) return false
    if (!Number.isFinite(incomingCreated)) return sameContent
    const localCreated = new Date(String(m.created_at ?? "")).getTime()
    if (!Number.isFinite(localCreated)) return sameContent
    return Math.abs(incomingCreated - localCreated) < 15_000
  })

  if (tempIndex >= 0) {
    const next = [...prev]
    next[tempIndex] = {
      ...prev[tempIndex],
      ...incoming,
      send_status: "sent",
      client_temp_id: undefined,
    }
    return next
  }

  return [...prev, { ...incoming, send_status: incoming.send_status ?? "sent" }]
}

export function markOptimisticMessageFailed<T extends { id?: unknown }>(
  prev: T[],
  tempId: string
): T[] {
  return prev.map((m) =>
    String(m.id) === tempId
      ? { ...m, send_status: "failed" as MessageSendStatus }
      : m
  )
}

export function replaceOptimisticMessage<T extends { id?: unknown }>(
  prev: T[],
  tempId: string,
  serverRow: T
): T[] {
  return prev.map((m) =>
    String(m.id) === tempId
      ? { ...serverRow, send_status: "sent" as MessageSendStatus }
      : m
  )
}
