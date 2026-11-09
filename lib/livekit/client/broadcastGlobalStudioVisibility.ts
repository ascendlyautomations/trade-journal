/**
 * Full-screen global broadcast studio (TradeRoomBroadcastGlobalChrome) should only appear
 * for **server-public** sessions. OBS private preparation stays in TradeRoomBroadcastPanel only.
 */

export type BroadcastGlobalStudioRole = "none" | "broadcaster" | "viewer" | "conversation"

export type BroadcastGlobalStudioPresentation = "hidden" | "studio" | "mini"

export type BroadcastGlobalStudioObsHostUiPhase =
  | "idle"
  | "preparing"
  | "waiting_for_encoder"
  | "preview_ready"
  | "publishing"
  | "public"
  | "error"

export type BroadcastGlobalStudioStatusSlice = {
  live?: boolean
  broadcastSessionId?: string
  videoSource?: string
  broadcastSource?: string
  publicLive?: boolean
  visibility?: "public" | "preparing"
}

/** Floating / full broadcaster chrome (mini or studio) while publishing. */
export function resolveBroadcastBroadcasterChromeVisible(options: {
  isPublishing: boolean
  role: BroadcastGlobalStudioRole
  studioPresentation: BroadcastGlobalStudioPresentation
  status: BroadcastGlobalStudioStatusSlice
  /** Active publisher session in this tab; ignore status rows for a different session. */
  publisherSessionId: string | null
  obsHostUiPhase: BroadcastGlobalStudioObsHostUiPhase | null
  obsBroadcastBootstrapping: boolean
}): boolean {
  if (!options.isPublishing || options.studioPresentation === "hidden") {
    return false
  }
  if (options.role !== "broadcaster") {
    return false
  }

  const sid = options.status.broadcastSessionId?.trim() ?? ""
  const pub = options.publisherSessionId?.trim() ?? ""
  if (!pub && !sid) {
    return false
  }
  if (!pub && sid) {
    return false
  }
  /** When publishing, `publisherSessionId` wins over stale status polls. */

  const videoSource = options.status.videoSource
  const broadcastSource = options.status.broadcastSource
  const isObsLike =
    videoSource === "obs" ||
    broadcastSource === "obs" ||
    options.obsHostUiPhase != null

  const publicLive = options.status.publicLive === true
  const visibility = options.status.visibility

  if (isObsLike) {
    if (!pub) {
      return false
    }
    const liveOk =
      options.status.live === true || (options.isPublishing && pub.length > 0)
    if (!liveOk) {
      return false
    }
    if (!publicLive || visibility !== "public") {
      return false
    }
    if (options.obsBroadcastBootstrapping || options.obsHostUiPhase !== "public") {
      return false
    }
  }

  return true
}

/** Floating / full viewer theater (mini or studio) while watching a public livestream. */
export function resolveBroadcastViewerChromeVisible(options: {
  isWatching: boolean
  role: BroadcastGlobalStudioRole
  studioPresentation: BroadcastGlobalStudioPresentation
  status: BroadcastGlobalStudioStatusSlice
}): boolean {
  if (!options.isWatching) return false
  if (options.role !== "viewer" && options.role !== "conversation") return false
  if (options.studioPresentation === "hidden") return false
  if (options.status.publicLive !== true) return false
  if (options.status.live !== true) return false
  const sid = options.status.broadcastSessionId?.trim() ?? ""
  if (!sid) return false
  return true
}

export function resolveBroadcastGlobalStudioChromeVisible(options: {
  isPublishing: boolean
  isWatching: boolean
  role: BroadcastGlobalStudioRole
  studioPresentation: BroadcastGlobalStudioPresentation
  status: BroadcastGlobalStudioStatusSlice
  publisherSessionId: string | null
  obsHostUiPhase: BroadcastGlobalStudioObsHostUiPhase | null
  obsBroadcastBootstrapping: boolean
}): boolean {
  if (
    resolveBroadcastBroadcasterChromeVisible({
      isPublishing: options.isPublishing,
      role: options.role,
      studioPresentation: options.studioPresentation,
      status: options.status,
      publisherSessionId: options.publisherSessionId,
      obsHostUiPhase: options.obsHostUiPhase,
      obsBroadcastBootstrapping: options.obsBroadcastBootstrapping,
    })
  ) {
    return true
  }
  return resolveBroadcastViewerChromeVisible({
    isWatching: options.isWatching,
    role: options.role,
    studioPresentation: options.studioPresentation,
    status: options.status,
  })
}

/** @deprecated Use `resolveBroadcastBroadcasterChromeVisible` */
export const resolveBroadcastGlobalStudioVisible = resolveBroadcastBroadcasterChromeVisible
