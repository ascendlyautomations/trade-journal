/** Mirrors `room_message_insert_allowed` media gate for Trade Room UI. */

export function tradeRoomMemberCanShareMedia(
  room:
    | {
        members_can_share_media?: boolean | null
      }
    | null
    | undefined,
  isOwner: boolean
): boolean {
  if (isOwner) return true
  return room?.members_can_share_media !== false
}
