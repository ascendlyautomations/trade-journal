/**
 * Derive viewer-discoverable "public live" from GET /api/livekit/broadcast/status.
 * Missing `visibility` must NOT imply public — that broke OBS private prep when lite polls omitted it.
 */
export function discoverableFromBroadcastStatusPayload(payload: {
  live?: boolean
  publicLive?: boolean
  visibility?: string | null
}): boolean {
  const sessionActive = Boolean(payload.live)
  return (
    payload.publicLive === true ||
    (sessionActive && payload.visibility === "public")
  )
}
