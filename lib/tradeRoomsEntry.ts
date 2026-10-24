import { readRoomSession } from "@/lib/roomSessionCache"

export type TradeRoomEntry = {
  id: string
  slug?: string | null
  owner_user_id?: string | null
}

/** Default room: owned room when present, otherwise first in list order. */
export function pickInitialTradeRoomId(
  rooms: TradeRoomEntry[],
  userId: string
): string | null {
  if (rooms.length === 0) return null
  const owned = rooms.find((r) => r.owner_user_id === userId)
  return owned?.id ?? rooms[0].id
}

export function tradeRoomUrlKey(room: TradeRoomEntry): string {
  const slug = room.slug?.trim()
  return slug && slug.length > 0 ? slug : room.id
}

/** Entry href for Trade Rooms — uses session cache only (no extra fetch). */
export function buildTradeRoomsEntryHref(userId: string | null | undefined): string {
  if (!userId) return "/trade-rooms"
  const cached = readRoomSession(userId)
  const rooms = (cached?.rooms ?? []) as TradeRoomEntry[]
  if (rooms.length === 0) return "/trade-rooms"
  const roomId = pickInitialTradeRoomId(rooms, userId)
  if (!roomId) return "/trade-rooms"
  const room = rooms.find((r) => r.id === roomId)
  if (!room) return "/trade-rooms"
  return `/community?room=${encodeURIComponent(tradeRoomUrlKey(room))}`
}
