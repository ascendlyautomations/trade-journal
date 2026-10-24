/** Canonical Trade Room link. Web redirects this into the room; iOS opens it as a universal link. */
export function tradeRoomSharePath(roomKey: string): string {
  const key = roomKey.trim()
  if (!key) return "/community"
  return `/room/${encodeURIComponent(key)}`
}

export function tradeRoomShareUrl(origin: string, roomKey: string): string {
  const base = origin.replace(/\/$/, "")
  return `${base}${tradeRoomSharePath(roomKey)}`
}
