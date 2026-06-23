export type RoomSharePostFields = {
  room_id?: string | null
  room_name?: string | null
  room_logo?: string | null
  room_description?: string | null
}

export type PendingRoomShareDraft = {
  roomId: string
  roomName: string
  roomLogo: string | null
  roomDescription: string | null
}

export function isRoomSharePost(
  post: RoomSharePostFields | null | undefined
): boolean {
  const id = post?.room_id
  return id != null && String(id).trim() !== ""
}

export function resolveRoomShareLogo(logo: string | null | undefined): string {
  const raw = logo != null ? String(logo).trim() : ""
  if (!raw) return "/default-avatar.png"
  return raw
}

export function formatRoomMemberCount(count: number): string {
  const n = Number.isFinite(count) ? Math.max(0, Math.floor(count)) : 0
  return n === 1 ? "1 member" : `${n.toLocaleString()} members`
}

export function buildRoomSharePostInsert(
  userId: string,
  draft: PendingRoomShareDraft,
  content?: string | null,
  imageUrl?: string | null
) {
  return {
    user_id: userId,
    content: content?.trim() ? content.trim() : null,
    image_url: imageUrl ?? null,
    room_id: draft.roomId,
    room_name: draft.roomName.trim() || "Trade Room",
    room_logo: draft.roomLogo,
    room_description: draft.roomDescription?.trim() || null,
  }
}

export function pendingRoomShareFromRoom(room: {
  id: string
  name?: string | null
  description?: string | null
  image_url?: string | null
}): PendingRoomShareDraft {
  return {
    roomId: String(room.id),
    roomName: room.name?.trim() || "Trade Room",
    roomLogo:
      room.image_url != null && String(room.image_url).trim() !== ""
        ? String(room.image_url).trim()
        : null,
    roomDescription: room.description?.trim() || null,
  }
}
