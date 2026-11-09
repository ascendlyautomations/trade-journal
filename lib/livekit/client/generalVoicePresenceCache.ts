/** Shared module cache for GET /api/livekit/voice/presence (web sidebar + hooks) */

export const PRESENCE_CACHE_MS = 60_000

export type GeneralVoicePresenceSnapshot = {
  connectedCount: number
  fetchedAt: number
}

export const generalVoicePresenceCache = new Map<
  string,
  GeneralVoicePresenceSnapshot
>()
/** One in-flight request per room so remounts / duplicate hooks share the same GET. */
export const generalVoicePresenceFetchByRoom = new Map<
  string,
  Promise<GeneralVoicePresenceSnapshot | null>
>()

/** After leaving LiveKit voice, drop cached counts so the UI refetches promptly */
export function invalidateGeneralVoicePresenceCache(roomId: string): void {
  const id = roomId.trim()
  if (!id) return
  generalVoicePresenceCache.delete(id)
}
