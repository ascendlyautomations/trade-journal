export type RoomSectionLiveKind = "text" | "voice_open" | "voice_stage"

export function normalizeLiveKind(raw: unknown): RoomSectionLiveKind {
  const v = String(raw ?? "text")
    .trim()
    .toLowerCase()
  if (v === "voice_open" || v === "voice_stage") return v
  return "text"
}

export function isVoiceLiveSection(liveKind: unknown): boolean {
  const k = normalizeLiveKind(liveKind)
  return k === "voice_open" || k === "voice_stage"
}
