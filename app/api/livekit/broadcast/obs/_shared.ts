export function parseObsSessionBody(
  raw: unknown
): { roomId: string; sessionId: string } | null {
  if (!raw || typeof raw !== "object") return null
  const b = raw as Record<string, unknown>
  const roomId = typeof b.roomId === "string" ? b.roomId.trim() : ""
  const sessionId = typeof b.sessionId === "string" ? b.sessionId.trim() : ""
  if (!roomId || !sessionId) return null
  return { roomId, sessionId }
}
