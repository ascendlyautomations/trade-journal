export type TradeRoomBroadcastLiveNotifyContent = {
  room_id: string
  room_slug: string
  room_name: string
  broadcast_session_id: string
  collapse_id: string
}

export function buildTradeRoomBroadcastLiveNotifyContent(input: {
  roomId: string
  roomSlug: string
  roomName: string
  broadcastSessionId: string
}): TradeRoomBroadcastLiveNotifyContent {
  const sessionId = input.broadcastSessionId.trim()
  return {
    room_id: input.roomId,
    room_slug: input.roomSlug.trim(),
    room_name: input.roomName.trim() || "Trade Room",
    broadcast_session_id: sessionId,
    collapse_id: `room-live:${sessionId}`,
  }
}
