const PREFIX = "tt/"

/** Stable LiveKit room name for a Trade Room voice section — must match server token + disconnect paths. */
export function liveKitRoomName(roomId: string, sectionId: string): string {
  const room = roomId.trim()
  const section = sectionId.trim()
  return `${PREFIX}${room}/${section}`
}

export function parseLiveKitRoomName(name: string): {
  roomId: string
  sectionId: string
} | null {
  const trimmed = name.trim()
  if (!trimmed.startsWith(PREFIX)) return null
  const rest = trimmed.slice(PREFIX.length)
  const slash = rest.indexOf("/")
  if (slash <= 0) return null
  const roomId = rest.slice(0, slash)
  const sectionId = rest.slice(slash + 1)
  if (!roomId || !sectionId) return null
  return { roomId, sectionId }
}
