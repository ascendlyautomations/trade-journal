type ShareScreenSnapshot = {
  isPublishing: boolean
  role: "none" | "broadcaster" | "viewer" | "conversation"
  status: {
    videoSource?: "screen" | "camera" | "obs"
    broadcastSource?: "browser" | "obs"
  }
}

/** User dismissed the browser screen-picker or denied permission — not a stream failure. */
export function isBroadcastScreenShareCancelled(err: unknown): boolean {
  if (err instanceof DOMException) {
    if (err.name === "NotAllowedError" || err.name === "AbortError") {
      return true
    }
  }
  if (err instanceof Error) {
    const m = err.message.toLowerCase()
    if (m.includes("permission") && m.includes("denied")) return true
    if (m.includes("cancel")) return true
  }
  return false
}

/**
 * Tab audio is optional. A browser that cannot capture it, or a token that
 * rejects the extra track, must fall back to video-only instead of failing the share.
 * User cancel and permission denial stay failures so the picker is not shown twice.
 */
export function shouldRetryBrowserScreenShareWithoutAudio(err: unknown): boolean {
  if (isBroadcastScreenShareCancelled(err)) return false
  if (!(err instanceof Error)) return false
  if (err.name === "NotSupportedError" || err.name === "OverconstrainedError") {
    return true
  }
  const message = err.message.toLowerCase()
  return message.includes("audio") || message.includes("insufficient permissions")
}

export function tradeRoomBroadcastShareScreenWhileLiveAvailable(
  snapshot: ShareScreenSnapshot
): boolean {
  if (!snapshot.isPublishing || snapshot.role !== "broadcaster") return false
  if (snapshot.status.broadcastSource === "obs") return false
  if (snapshot.status.videoSource === "obs") return false
  return snapshot.status.videoSource === "camera"
}

export function tradeRoomBroadcastScreenShareProgramActive(
  snapshot: ShareScreenSnapshot
): boolean {
  if (!snapshot.isPublishing || snapshot.role !== "broadcaster") return false
  if (snapshot.status.broadcastSource === "obs") return false
  if (snapshot.status.videoSource === "obs") return false
  return snapshot.status.videoSource === "screen"
}
