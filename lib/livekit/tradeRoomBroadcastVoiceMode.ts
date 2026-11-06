export type TradeRoomBroadcastVoiceMode = "broadcast_only" | "open_voice"

export type TradeRoomBroadcastVideoSource = "screen" | "camera"

export function normalizeTradeRoomBroadcastVoiceMode(
  raw: string | null | undefined
): TradeRoomBroadcastVoiceMode {
  const v = (raw ?? "broadcast_only").trim().toLowerCase()
  return v === "open_voice" ? "open_voice" : "broadcast_only"
}

export function normalizeTradeRoomBroadcastVideoSource(
  raw: string | null | undefined
): TradeRoomBroadcastVideoSource {
  const v = (raw ?? "screen").trim().toLowerCase()
  return v === "camera" ? "camera" : "screen"
}
