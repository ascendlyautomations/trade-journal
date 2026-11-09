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
