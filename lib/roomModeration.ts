type RoomMessageLike = {
  user_id: string
  type?: string | null
}

export function isRoomOwner(
  ownerUserId: string | null | undefined,
  viewerUserId: string | null | undefined
): boolean {
  if (!ownerUserId || !viewerUserId) return false
  return ownerUserId === viewerUserId
}

export function isOwnRoomMessage(
  viewerUserId: string | null | undefined,
  message: { user_id: string }
): boolean {
  if (!viewerUserId) return false
  return message.user_id === viewerUserId
}

export function isTextRoomMessage(message: RoomMessageLike): boolean {
  const type = message.type != null ? String(message.type).trim().toLowerCase() : ""
  return type === "" || type === "text"
}

/** Authors may edit only their own text messages. Owners cannot edit others' messages. */
export function canEditRoomMessage(
  viewerUserId: string | null | undefined,
  message: RoomMessageLike
): boolean {
  if (!isOwnRoomMessage(viewerUserId, message)) return false
  return isTextRoomMessage(message)
}

/** Authors may delete own messages; room owners may delete any message in their room. */
export function canDeleteRoomMessage(
  viewerUserId: string | null | undefined,
  message: { user_id: string },
  options: { isRoomOwner: boolean }
): boolean {
  if (!viewerUserId) return false
  if (isOwnRoomMessage(viewerUserId, message)) return true
  return options.isRoomOwner
}

export function canModerateRoomMessage(
  viewerUserId: string | null | undefined,
  message: RoomMessageLike,
  options: { isRoomOwner: boolean }
): boolean {
  return (
    canEditRoomMessage(viewerUserId, message) ||
    canDeleteRoomMessage(viewerUserId, message, options)
  )
}
