import { validateTradeRoomBroadcastStreamTitle } from "@/lib/livekit/tradeRoomBroadcastStreamTitle.ts"

export function parseRoomIdBody(raw: unknown): { roomId: string } | null {
  if (!raw || typeof raw !== "object") return null
  const b = raw as Record<string, unknown>
  const roomId = typeof b.roomId === "string" ? b.roomId.trim() : ""
  if (!roomId) return null
  return { roomId }
}

export function parseStartBody(
  raw: unknown
):
  | {
      roomId: string
      voiceMode: "broadcast_only" | "open_voice"
      videoSource: "screen" | "camera" | "obs"
      streamTitle: string
    }
  | { error: string }
  | null {
  if (!raw || typeof raw !== "object") return null
  const b = raw as Record<string, unknown>
  const roomId = typeof b.roomId === "string" ? b.roomId.trim() : ""
  if (!roomId) return null
  const titleCheck = validateTradeRoomBroadcastStreamTitle(b.streamTitle)
  if (!titleCheck.ok) return { error: titleCheck.error }
  const voiceModeRaw =
    typeof b.voiceMode === "string" ? b.voiceMode.trim().toLowerCase() : "broadcast_only"
  const voiceMode =
    voiceModeRaw === "open_voice" ? "open_voice" : ("broadcast_only" as const)
  const videoSourceRaw =
    typeof b.videoSource === "string" ? b.videoSource.trim().toLowerCase() : "screen"
  let videoSource: "screen" | "camera" | "obs" = "screen"
  if (videoSourceRaw === "camera") videoSource = "camera"
  else if (videoSourceRaw === "obs") videoSource = "obs"
  return {
    roomId,
    voiceMode,
    videoSource,
    streamTitle: titleCheck.title,
  }
}

export function parseStreamTitleBody(
  raw: unknown
):
  | { roomId: string; sessionId: string; streamTitle: string }
  | { error: string }
  | null {
  if (!raw || typeof raw !== "object") return null
  const b = raw as Record<string, unknown>
  const roomId = typeof b.roomId === "string" ? b.roomId.trim() : ""
  const sessionId = typeof b.sessionId === "string" ? b.sessionId.trim() : ""
  if (!roomId || !sessionId) return null
  const titleCheck = validateTradeRoomBroadcastStreamTitle(b.streamTitle)
  if (!titleCheck.ok) return { error: titleCheck.error }
  return { roomId, sessionId, streamTitle: titleCheck.title }
}

export function parseStopBody(
  raw: unknown
): { roomId: string; sessionId: string } | null {
  if (!raw || typeof raw !== "object") return null
  const b = raw as Record<string, unknown>
  const roomId = typeof b.roomId === "string" ? b.roomId.trim() : ""
  const sessionId = typeof b.sessionId === "string" ? b.sessionId.trim() : ""
  if (!roomId || !sessionId) return null
  return { roomId, sessionId }
}
