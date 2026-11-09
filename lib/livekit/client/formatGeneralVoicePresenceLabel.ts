/** Presence line for General Voice sidebar (connected count only; no speaking counter). */
export function formatGeneralVoicePresenceLabel(
  connectedCount: number | null | undefined
): string | null {
  if (connectedCount == null || connectedCount < 0) return null
  if (connectedCount === 0) return "No one in voice"
  return connectedCount === 1 ? "1 in voice" : `${connectedCount} in voice`
}
