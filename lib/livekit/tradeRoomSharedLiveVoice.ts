/** One shared LiveKit voice channel per Trade Room (not per text section). */

export const TRADE_ROOM_GENERAL_VOICE_LABEL = "General Voice"

export const LIVEKIT_TRADE_ROOM_VOICE_SEGMENT = "voice"

export type TradeRoomLiveVoiceKind = "off" | "voice_open" | "voice_stage"

export function normalizeTradeRoomLiveVoiceKind(
  raw: string | null | undefined
): TradeRoomLiveVoiceKind {
  const v = (raw ?? "voice_open").trim().toLowerCase()
  if (v === "off" || v === "voice_open" || v === "voice_stage") return v
  return "voice_open"
}

export function tradeRoomSupportsSharedLiveVoice(
  kind: TradeRoomLiveVoiceKind
): boolean {
  return kind === "voice_open" || kind === "voice_stage"
}
