/**
 * Classifies viewer LiveKit disconnects (parity with native `handleViewerLiveKitDisconnect`).
 */

export type ViewerBroadcastDisconnectAction =
  | { type: "stream_ended" }
  | { type: "removed"; blocked: boolean }
  | { type: "connection_lost" }

export function classifyViewerBroadcastDisconnect(params: {
  watchingSessionId: string
  statusLive: boolean
  statusSessionId: string | null | undefined
  snapshot:
    | {
        sessionId?: string
        blockedFromBroadcastRejoin?: boolean
        presentInLiveKitBroadcastRoom?: boolean
        sessionBlocks?: string[]
      }
    | null
    | undefined
  viewerUserId: string | null
}): ViewerBroadcastDisconnectAction {
  const {
    watchingSessionId,
    statusLive,
    statusSessionId,
    snapshot,
    viewerUserId,
  } = params

  if (!statusLive) {
    return { type: "stream_ended" }
  }
  if (statusSessionId && statusSessionId !== watchingSessionId) {
    return { type: "stream_ended" }
  }
  // A missing interactive snapshot is not proof the stream ended. Status can
  // still be live when the follow-up request fails or times out — offer Retry.
  if (!snapshot) {
    return { type: "connection_lost" }
  }

  const blocked =
    snapshot.blockedFromBroadcastRejoin === true ||
    (viewerUserId != null &&
      (snapshot.sessionBlocks ?? []).includes(viewerUserId))

  if (blocked) {
    return { type: "removed", blocked: true }
  }

  if (snapshot.presentInLiveKitBroadcastRoom !== true) {
    return { type: "removed", blocked: false }
  }

  return { type: "connection_lost" }
}
