const MIC_ACCESS_ERROR_NAMES = new Set([
  "NotFoundError",
  "NotAllowedError",
  "NotReadableError",
  "OverconstrainedError",
])

export function isLiveVoiceMicrophoneAccessError(err: unknown): boolean {
  if (!err || typeof err !== "object") return false
  const name = "name" in err ? String((err as { name: unknown }).name) : ""
  if (MIC_ACCESS_ERROR_NAMES.has(name)) return true
  const message =
    "message" in err ? String((err as { message: unknown }).message) : ""
  return /not found|not allowed|not readable|permission|device/i.test(message)
}

export function liveVoiceMicrophoneErrorMessage(err: unknown): string {
  const name =
    err && typeof err === "object" && "name" in err
      ? String((err as { name: unknown }).name)
      : ""
  switch (name) {
    case "NotFoundError":
      return "No microphone was found on this device."
    case "NotAllowedError":
      return "Microphone access was blocked. Check browser permissions."
    case "NotReadableError":
      return "Your microphone is in use or unavailable."
    case "OverconstrainedError":
      return "This microphone could not be used for live voice."
    default:
      return "Could not open the microphone."
  }
}

export const LIVE_VOICE_LISTEN_ONLY_SUFFIX =
  " You can still listen to the channel."
