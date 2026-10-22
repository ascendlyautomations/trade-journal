export type TradeRoomKind = "community" | "official" | string | null | undefined

export function canManageTradeRoom(options: {
  viewerId: string | null | undefined
  ownerUserId: string | null | undefined
  roomKind?: TradeRoomKind
  isPlatformAdmin?: boolean
}): boolean {
  const { viewerId, ownerUserId, roomKind, isPlatformAdmin } = options
  if (!viewerId) return false
  if (ownerUserId && viewerId === ownerUserId) return true
  return Boolean(isPlatformAdmin && roomKind === "official")
}

export function canDeleteTradeRoom(options: {
  viewerId: string | null | undefined
  ownerUserId: string | null | undefined
  roomKind?: TradeRoomKind
}): boolean {
  const { viewerId, ownerUserId, roomKind } = options
  if (!viewerId || !ownerUserId || viewerId !== ownerUserId) return false
  return roomKind !== "official"
}
