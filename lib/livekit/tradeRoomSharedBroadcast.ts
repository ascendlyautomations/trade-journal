/** LiveKit broadcast segment for Trade Room screen share (separate from voice). */

export const LIVEKIT_TRADE_ROOM_BROADCAST_SEGMENT = "broadcast"

/** Phase 1: room owner or elevated moderators may start broadcasting. */
export function mayStartTradeRoomBroadcast(flags: {
  isOwner: boolean
  canManage: boolean
  canModerate: boolean
}): boolean {
  return flags.isOwner || flags.canManage || flags.canModerate
}
