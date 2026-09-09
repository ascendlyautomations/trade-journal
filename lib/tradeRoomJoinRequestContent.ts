export type TradeRoomJoinRequestNotificationStatus =
  | "pending"
  | "approved"
  | "rejected"

export type TradeRoomJoinRequestContent = {
  join_request_id: string
  room_slug: string | null
  room_name: string | null
  request_status?: TradeRoomJoinRequestNotificationStatus
  href?: string
}

export function buildTradeRoomJoinRequestContent(input: {
  joinRequestId: string
  roomSlug: string | null
  roomName: string | null
  requestStatus?: TradeRoomJoinRequestNotificationStatus
  href?: string
}): string {
  const payload: TradeRoomJoinRequestContent = {
    join_request_id: input.joinRequestId,
    room_slug: input.roomSlug,
    room_name: input.roomName,
    request_status: input.requestStatus ?? "pending",
  }
  if (input.href?.trim()) {
    payload.href = input.href.trim()
  }
  return JSON.stringify(payload)
}

export function parseTradeRoomJoinRequestContent(
  content: string | null | undefined
): TradeRoomJoinRequestContent | null {
  if (!content?.trim()) return null
  try {
    const parsed = JSON.parse(content) as Record<string, unknown>
    const joinRequestId =
      typeof parsed.join_request_id === "string"
        ? parsed.join_request_id.trim()
        : ""
    if (!joinRequestId) return null
    const statusRaw =
      typeof parsed.request_status === "string"
        ? parsed.request_status.trim().toLowerCase()
        : "pending"
    const requestStatus: TradeRoomJoinRequestNotificationStatus =
      statusRaw === "approved" || statusRaw === "rejected"
        ? statusRaw
        : "pending"
    return {
      join_request_id: joinRequestId,
      room_slug:
        typeof parsed.room_slug === "string" ? parsed.room_slug.trim() : null,
      room_name:
        typeof parsed.room_name === "string" ? parsed.room_name.trim() : null,
      request_status: requestStatus,
      href: typeof parsed.href === "string" ? parsed.href.trim() : undefined,
    }
  } catch {
    return null
  }
}

export function buildTradeRoomJoinRequestHref(requestId: string): string {
  return `/notifications?joinRequest=${encodeURIComponent(requestId)}`
}

export function buildTradeRoomJoinAcceptedContent(input: {
  roomSlug: string | null
  roomName: string | null
  href?: string
}): string {
  return JSON.stringify({
    room_slug: input.roomSlug,
    room_name: input.roomName,
    href: input.href ?? undefined,
  })
}

export function buildTradeRoomJoinDeclinedContent(input: {
  roomSlug: string | null
  roomName: string | null
}): string {
  return JSON.stringify({
    room_slug: input.roomSlug,
    room_name: input.roomName,
  })
}
