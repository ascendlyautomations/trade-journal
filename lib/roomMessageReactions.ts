/** V1 Trade Room message reactions (Trade Rooms only). */

export const ROOM_MESSAGE_REACTIONS = ["👍", "🔥", "😂", "‼️"] as const

export type RoomMessageReactionEmoji = (typeof ROOM_MESSAGE_REACTIONS)[number]

export type RoomMessageReactionRow = {
  id: string
  message_id: string
  user_id: string
  reaction: string
  created_at?: string
}

export type RoomMessageReactionSummary = {
  emoji: RoomMessageReactionEmoji
  count: number
  reactedByViewer: boolean
}

export function aggregateRoomMessageReactions(
  reactions: RoomMessageReactionRow[] | null | undefined,
  viewerUserId: string | null | undefined
): RoomMessageReactionSummary[] {
  const counts = new Map<RoomMessageReactionEmoji, number>()
  const viewerSet = new Set<RoomMessageReactionEmoji>()

  for (const row of reactions ?? []) {
    if (!ROOM_MESSAGE_REACTIONS.includes(row.reaction as RoomMessageReactionEmoji)) {
      continue
    }
    const emoji = row.reaction as RoomMessageReactionEmoji
    counts.set(emoji, (counts.get(emoji) ?? 0) + 1)
    if (viewerUserId && row.user_id === viewerUserId) {
      viewerSet.add(emoji)
    }
  }

  return ROOM_MESSAGE_REACTIONS.flatMap((emoji) => {
    const count = counts.get(emoji) ?? 0
    if (count === 0) return []
    return [{ emoji, count, reactedByViewer: viewerSet.has(emoji) }]
  })
}

export function patchRoomMessageReactions(
  reactions: RoomMessageReactionRow[] | null | undefined,
  next: RoomMessageReactionRow,
  mode: "insert" | "delete"
): RoomMessageReactionRow[] {
  const list = reactions ?? []
  if (mode === "insert") {
    if (
      list.some(
        (row) =>
          row.id === next.id ||
          (row.user_id === next.user_id && row.reaction === next.reaction)
      )
    ) {
      return list
    }
    return [...list, next]
  }

  return list.filter((row) => row.id !== next.id)
}
