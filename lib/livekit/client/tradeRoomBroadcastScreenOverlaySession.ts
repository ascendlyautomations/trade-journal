import {
  LocalVideoTrack,
  Track,
  isLocalTrack,
  type Room,
} from "livekit-client"
import { findLocalBroadcastVideoPublication } from "./tradeRoomBroadcastLocalPreview.ts"
import { BroadcastScreenOverlayCompositor } from "./tradeRoomBroadcastScreenOverlayCompositor.ts"
import {
  DEFAULT_SCREEN_CAMERA_OVERLAY_POSITION,
  type ScreenCameraOverlayPosition,
} from "./tradeRoomBroadcastScreenOverlayTypes.ts"
import { logBroadcast } from "./tradeRoomBroadcastDiagnostics.ts"

export type EnableScreenCameraOverlayOptions = {
  reuseCameraTrack?: MediaStreamTrack
}

type OverlaySession = {
  compositor: BroadcastScreenOverlayCompositor
  /** Raw display capture — kept live for compositor + restore via replaceTrack. */
  screenTrack: MediaStreamTrack
  /** Existing screen-share publication; media track swapped to composite while overlay is on. */
  publishedScreenTrack: LocalVideoTrack
  cameraStream: MediaStream | null
  /** When false, camera track is borrowed from the live camera publication (do not stop on teardown). */
  releaseCameraTrackOnTeardown: boolean
  position: ScreenCameraOverlayPosition
  cameraVisible: boolean
}

let session: OverlaySession | null = null
let overlaySessionEpoch = 0

/** Bumped whenever overlay/capture state is torn down — async enable paths can ignore stale work. */
export function getScreenOverlaySessionEpoch(): number {
  return overlaySessionEpoch
}

function bumpOverlaySessionEpoch(): void {
  overlaySessionEpoch += 1
}

export function stopLiveMediaStreamTracks(
  tracks: Iterable<MediaStreamTrack>
): number {
  let stopped = 0
  for (const track of tracks) {
    if (track.readyState === "live") {
      try {
        track.stop()
        stopped += 1
      } catch {
        // ignore stale stop
      }
    }
  }
  return stopped
}

function isLocalScreenShareSource(source: Track.Source): boolean {
  return (
    source === Track.Source.ScreenShare ||
    source === Track.Source.ScreenShareAudio
  )
}

function collectLocalScreenShareMediaTracks(room: Room): MediaStreamTrack[] {
  const out: MediaStreamTrack[] = []
  const seen = new Set<string>()
  for (const pub of room.localParticipant.videoTrackPublications.values()) {
    if (!isLocalScreenShareSource(pub.source)) continue
    for (const media of [
      pub.track?.mediaStreamTrack,
      pub.videoTrack?.mediaStreamTrack,
    ]) {
      if (!media || seen.has(media.id)) continue
      seen.add(media.id)
      out.push(media)
    }
  }
  return out
}

/**
 * Stops overlay compositor + owned display/PiP tracks and unpublishes local screen share.
 * Safe to call more than once (idempotent via session clear + track readyState).
 */
export async function releaseBrowserScreenShareCapture(
  room: Room | null | undefined,
  options?: { stopDisplayCapture?: boolean }
): Promise<void> {
  const stopDisplay = options?.stopDisplayCapture !== false
  bumpOverlaySessionEpoch()
  const s = session
  session = null

  if (s) {
    s.compositor.stop()
    releaseOverlayCameraTrack(s)
    if (stopDisplay) {
      stopLiveMediaStreamTracks([s.screenTrack])
    }
    logBroadcast("screen capture overlay released", {
      stopDisplayCapture: stopDisplay,
      screenTrackId: s.screenTrack.id,
      screenReadyState: s.screenTrack.readyState,
    })
  }

  if (stopDisplay && room) {
    const before = collectLocalScreenShareMediaTracks(room)
    try {
      await room.localParticipant.setScreenShareEnabled(false)
    } catch (err) {
      logOverlayStep("setScreenShareEnabled(false) failed", mediaTrackErrorFields(err))
    }
    const after = collectLocalScreenShareMediaTracks(room)
    const stopped = stopLiveMediaStreamTracks([...before, ...after])
    logBroadcast("local screen share tracks stopped", {
      trackCount: stopped,
    })
  }
}

function logOverlayStep(
  step: string,
  details?: Record<string, unknown>
): void {
  logBroadcast(`screen overlay step — ${step}`, details)
}

function mediaTrackErrorFields(err: unknown): Record<string, unknown> {
  if (err instanceof DOMException) {
    return { errorName: err.name, message: err.message, code: err.code }
  }
  if (err instanceof Error) {
    return { errorName: err.name, message: err.message }
  }
  return { message: String(err) }
}

export function getScreenOverlaySessionActive(): boolean {
  return session != null
}

export function getScreenOverlayPosition(): ScreenCameraOverlayPosition {
  return session?.position ?? DEFAULT_SCREEN_CAMERA_OVERLAY_POSITION
}

export function isScreenOverlayCameraVisible(): boolean {
  return session?.cameraVisible === true
}

export function getScreenOverlayRawScreenTrack(): MediaStreamTrack | null {
  const track = session?.screenTrack
  return track?.readyState === "live" ? track : null
}

export async function stopScreenCameraOverlaySession(
  room?: Room | null
): Promise<void> {
  await releaseBrowserScreenShareCapture(room ?? null, {
    stopDisplayCapture: true,
  })
}

function resolvePublishedScreenVideoTrack(room: Room): {
  published: LocalVideoTrack
  rawScreenTrack: MediaStreamTrack
} {
  if (session?.publishedScreenTrack && session.screenTrack.readyState === "live") {
    return {
      published: session.publishedScreenTrack,
      rawScreenTrack: session.screenTrack,
    }
  }

  const pub = findLocalBroadcastVideoPublication(room, "screen")
  const track = pub?.track
  if (
    !track ||
    !isLocalTrack(track) ||
    track.kind !== Track.Kind.Video
  ) {
    throw new Error("No published local screen-share track is available for overlay.")
  }
  const published = track as LocalVideoTrack
  const raw = published.mediaStreamTrack
  if (!raw || raw.readyState !== "live") {
    throw new Error("Screen share track is not live.")
  }
  return { published, rawScreenTrack: raw }
}

async function acquireCameraTrack(): Promise<MediaStreamTrack> {
  logOverlayStep("camera getUserMedia start")
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      video: {
        facingMode: "user",
        width: { ideal: 640 },
        height: { ideal: 360 },
        frameRate: { ideal: 24, max: 30 },
      },
      audio: false,
    })
    const track = stream.getVideoTracks()[0]
    if (!track) {
      stream.getTracks().forEach((t) => t.stop())
      throw new Error("No camera video track was returned.")
    }
    logOverlayStep("camera getUserMedia ok", {
      trackId: track.id,
      readyState: track.readyState,
      label: track.label,
    })
    return track
  } catch (err) {
    logOverlayStep("camera getUserMedia failed", mediaTrackErrorFields(err))
    const msg =
      err instanceof Error ? err.message : "Could not open the camera for overlay."
    throw new Error(msg)
  }
}

/**
 * Composite screen + camera and swap onto the existing screen-share publication via replaceTrack
 * (does not unpublish — avoids stopLocalTrackOnUnpublish killing display capture).
 */
function releaseOverlayCameraTrack(s: OverlaySession): void {
  if (s.releaseCameraTrackOnTeardown) {
    s.cameraStream?.getTracks().forEach((t) => t.stop())
  }
  s.cameraStream = null
}

export async function enableScreenCameraOverlay(
  room: Room,
  position: ScreenCameraOverlayPosition = DEFAULT_SCREEN_CAMERA_OVERLAY_POSITION,
  options?: EnableScreenCameraOverlayOptions
): Promise<void> {
  const enableEpoch = overlaySessionEpoch
  if (session) {
    session.position = position
    session.compositor.setPosition(position)
    session.compositor.setShowCamera(true)
    session.cameraVisible = true
    return
  }

  const { published, rawScreenTrack } = resolvePublishedScreenVideoTrack(room)
  logOverlayStep("resolved screen publication", {
    trackSid: published.sid ?? null,
    screenTrackId: rawScreenTrack.id,
    screenReadyState: rawScreenTrack.readyState,
  })

  let cameraStream: MediaStream | null = null
  let releaseCameraTrackOnTeardown = true
  let cameraTrack: MediaStreamTrack
  const reuse = options?.reuseCameraTrack
  if (reuse && reuse.readyState === "live") {
    cameraTrack = reuse
    releaseCameraTrackOnTeardown = false
    logOverlayStep("reusing live camera publication track", {
      trackId: reuse.id,
      label: reuse.label,
    })
  } else {
    cameraTrack = await acquireCameraTrack()
    cameraStream = new MediaStream([cameraTrack])
  }

  const compositor = new BroadcastScreenOverlayCompositor({
    screenTrack: rawScreenTrack,
    cameraTrack,
    position,
    showCamera: true,
  })

  let compositeMedia: MediaStreamTrack
  try {
    logOverlayStep("compositor start")
    compositeMedia = await compositor.start()
    await compositor.warmupFrames(2)
    const health = compositor.getHealth()
    logOverlayStep("compositor warmup done", health)
    if (compositeMedia.readyState !== "live") {
      throw new Error(
        `Composite captureStream track is not live (readyState=${compositeMedia.readyState}).`
      )
    }
  } catch (err) {
    compositor.stop()
    if (releaseCameraTrackOnTeardown) {
      cameraStream?.getTracks().forEach((t) => t.stop())
    }
    logOverlayStep("compositor failed", mediaTrackErrorFields(err))
    throw err
  }

  try {
    logOverlayStep("replaceTrack → composite", {
      publicationSid: published.sid ?? null,
      compositeTrackId: compositeMedia.id,
    })
    await published.replaceTrack(compositeMedia, { userProvidedTrack: true })
    logOverlayStep("replaceTrack ok", {
      publicationSid: published.sid ?? null,
      publishedMediaId: published.mediaStreamTrack.id,
      compositeTrackId: compositeMedia.id,
      compositeReadyState: compositeMedia.readyState,
    })
    logBroadcast("browser screen program replaceTrack (viewers should resync program)", {
      publicationSid: published.sid ?? null,
      videoSource: "screen",
    })
  } catch (err) {
    compositor.stop()
    if (releaseCameraTrackOnTeardown) {
      cameraStream?.getTracks().forEach((t) => t.stop())
    }
    logOverlayStep("replaceTrack failed", mediaTrackErrorFields(err))
    throw err instanceof Error
      ? err
      : new Error("Could not publish the composed screen overlay.")
  }

  session = {
    compositor,
    screenTrack: rawScreenTrack,
    publishedScreenTrack: published,
    cameraStream,
    releaseCameraTrackOnTeardown,
    position,
    cameraVisible: true,
  }
  if (enableEpoch !== overlaySessionEpoch) {
    compositor.stop()
    releaseOverlayCameraTrack({
      compositor,
      screenTrack: rawScreenTrack,
      publishedScreenTrack: published,
      cameraStream,
      releaseCameraTrackOnTeardown,
      position,
      cameraVisible: true,
    })
    stopLiveMediaStreamTracks([rawScreenTrack, compositeMedia])
    session = null
    throw new Error("Screen overlay was cancelled before publish finished.")
  }
  logBroadcast("screen overlay enabled", { position, trackSid: published.sid ?? null })
}

export async function setScreenOverlayCameraVisible(
  room: Room,
  visible: boolean
): Promise<void> {
  if (!session) {
    if (visible) {
      await enableScreenCameraOverlay(room)
    }
    return
  }

  session.cameraVisible = visible
  session.compositor.setShowCamera(visible)

  if (!visible) {
    if (session.releaseCameraTrackOnTeardown) {
      session.cameraStream?.getTracks().forEach((t) => t.stop())
    }
    session.cameraStream = null
    session.compositor.setCameraTrack(null)
    return
  }

  if (!session.cameraStream || session.cameraStream.getVideoTracks().length === 0) {
    const cameraTrack = await acquireCameraTrack()
    session.cameraStream = new MediaStream([cameraTrack])
    session.compositor.setCameraTrack(cameraTrack)
  }
}

export async function setScreenCameraOverlayPosition(
  _room: Room,
  position: ScreenCameraOverlayPosition
): Promise<void> {
  if (!session) return
  session.position = position
  session.compositor.setPosition(position)
  logBroadcast("screen overlay position", { position })
}

export async function disableScreenCameraOverlay(room: Room): Promise<void> {
  if (!session) return

  const { screenTrack, publishedScreenTrack, compositor } = session
  try {
    logOverlayStep("replaceTrack → raw screen restore", {
      screenTrackId: screenTrack.id,
      screenReadyState: screenTrack.readyState,
    })
    if (screenTrack.readyState === "live") {
      await publishedScreenTrack.replaceTrack(screenTrack, {
        userProvidedTrack: true,
      })
    } else {
      logOverlayStep("raw screen track ended — cannot restore", {
        screenReadyState: screenTrack.readyState,
      })
    }
  } catch (err) {
    logOverlayStep("replaceTrack restore failed", mediaTrackErrorFields(err))
    throw err
  } finally {
    const active = session
    compositor.stop()
    if (active) {
      releaseOverlayCameraTrack(active)
    }
    session = null
    bumpOverlaySessionEpoch()
    logBroadcast("screen overlay disabled")
  }
}
