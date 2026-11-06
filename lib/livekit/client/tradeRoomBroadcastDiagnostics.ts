/** Development-only broadcast tracing — never log tokens or secrets. */

const PREFIX = "[TradeTraxs Broadcast]"

export function isBroadcastDiagnosticsEnabled(): boolean {
  return process.env.NODE_ENV === "development"
}

export function logBroadcast(
  event: string,
  details?: Record<string, unknown>
): void {
  if (!isBroadcastDiagnosticsEnabled()) return
  if (details && Object.keys(details).length > 0) {
    console.info(PREFIX, event, details)
  } else {
    console.info(PREFIX, event)
  }
}

export function logBroadcastVideoElementHealth(
  label: string,
  videoEl: HTMLVideoElement
): void {
  if (!isBroadcastDiagnosticsEnabled()) return
  const stream = videoEl.srcObject as MediaStream | null
  const videoTracks = stream?.getVideoTracks() ?? []
  logBroadcast(`${label} video element health`, {
    readyState: videoEl.readyState,
    videoWidth: videoEl.videoWidth,
    videoHeight: videoEl.videoHeight,
    paused: videoEl.paused,
    muted: videoEl.muted,
    mediaStreamTrackCount: videoTracks.length,
    mediaStreamTrackEnabled: videoTracks[0]?.enabled ?? null,
    mediaStreamTrackReadyState: videoTracks[0]?.readyState ?? null,
  })
}
