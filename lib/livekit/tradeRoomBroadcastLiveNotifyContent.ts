export type TradeRoomBroadcastLiveNotifyContent = {
  room_id: string
  room_slug: string
  room_name: string
  broadcast_session_id: string
  stream_title: string
  collapse_id: string
}

export function buildTradeRoomBroadcastLiveNotifyContent(input: {
  roomId: string
  roomSlug: string
  roomName: string
  broadcastSessionId: string
  streamTitle: string
}): TradeRoomBroadcastLiveNotifyContent {
  const sessionId = input.broadcastSessionId.trim()
  return {
    room_id: input.roomId,
    room_slug: input.roomSlug.trim(),
    room_name: input.roomName.trim() || "Trade Room",
    broadcast_session_id: sessionId,
    stream_title: input.streamTitle.trim(),
    collapse_id: `room-live:${sessionId}`,
  }
}
