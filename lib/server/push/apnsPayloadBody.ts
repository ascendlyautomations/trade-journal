export type ApnsAlertPayload = {
  title: string
  body: string
  href: string
  badge?: number
  notificationType: string
  category?: string
  conversationId?: string
  roomId?: string
  roomSlug?: string
  followRequestId?: string
  joinRequestId?: string
  senderId?: string
  threadId?: string
  collapseId?: string
}

/** Central APNs JSON body — all user-facing alerts must include `aps.sound`. */
export function buildApnsAlertPayloadBody(payload: ApnsAlertPayload): string {
  return JSON.stringify({
    aps: {
      alert: {
        title: payload.title,
        body: payload.body,
      },
      ...(typeof payload.badge === "number"
        ? { badge: Math.max(0, Math.floor(payload.badge)) }
        : {}),
      sound: "default",
      ...(payload.category ? { category: payload.category } : {}),
      ...(payload.threadId ? { "thread-id": payload.threadId } : {}),
    },
    href: payload.href,
    type: payload.notificationType,
    ...(payload.conversationId
      ? { conversationId: payload.conversationId }
      : {}),
    ...(payload.roomId ? { roomId: payload.roomId } : {}),
    ...(payload.roomSlug ? { roomSlug: payload.roomSlug } : {}),
    ...(payload.followRequestId
      ? { followRequestId: payload.followRequestId }
      : {}),
    ...(payload.joinRequestId ? { joinRequestId: payload.joinRequestId } : {}),
    ...(payload.senderId ? { senderId: payload.senderId } : {}),
  })
}
