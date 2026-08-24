export type RoomUnreadPatch = Record<string, boolean>

export function isRoomNotificationType(type: unknown): boolean {
  const t = String(type ?? "")
  return t === "room_message" || t === "room_mention" || t === "room_join"
}

export function extractRoomIdFromNotification(
  row: Record<string, unknown>
): string | null {
  if (row.room_id != null && String(row.room_id).trim()) {
    return String(row.room_id)
  }
  try {
    const content = row.content
    if (typeof content === "string" && content.trim().startsWith("{")) {
      const parsed = JSON.parse(content) as { room_id?: string }
      if (parsed.room_id) return String(parsed.room_id)
    }
  } catch {
    /* ignore */
  }
  return null
}

export function stableSortedRoomIds(ids: readonly string[]): string[] {
  return [
    ...new Set(
      ids
        .map((id) => String(id ?? "").trim())
        .filter((id) => id.length > 0)
    ),
  ].sort()
}

export function shouldSkipUnreadIncrement(args: {
  roomId: string
  selectedRoomId: string | null
  isRoomMarkedRead: (roomId: string) => boolean
}): boolean {
  if (args.selectedRoomId !== args.roomId) return false
  return args.isRoomMarkedRead(args.roomId)
}
