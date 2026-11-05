export type LiveKitServerConfig = {
  livekitUrl: string
  apiKey: string
  apiSecret: string
  maxParticipants: number
  tokenTtlSeconds: number
}

function parsePositiveInt(raw: string | undefined, fallback: number): number {
  const n = Number(raw?.trim())
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback
}

/** LiveKit Cloud / self-hosted credentials — server-only, never exposed to clients except public WSS URL. */
export function readLiveKitServerConfig(): LiveKitServerConfig | null {
  const livekitUrl = process.env.LIVEKIT_URL?.trim()
  const apiKey = process.env.LIVEKIT_API_KEY?.trim()
  const apiSecret = process.env.LIVEKIT_API_SECRET?.trim()
  if (!livekitUrl || !apiKey || !apiSecret) return null

  return {
    livekitUrl,
    apiKey,
    apiSecret,
    maxParticipants: parsePositiveInt(process.env.LIVEKIT_MAX_PARTICIPANTS, 25),
    tokenTtlSeconds: parsePositiveInt(process.env.LIVEKIT_TOKEN_TTL_SECONDS, 900),
  }
}

export function isLiveKitConfigured(): boolean {
  return readLiveKitServerConfig() != null
}
