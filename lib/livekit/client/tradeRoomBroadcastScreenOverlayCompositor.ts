import {
  screenOverlayPipRect,
  screenOverlayPipSize,
  SCREEN_OVERLAY_CORNER_RADIUS_PX,
} from "./tradeRoomBroadcastScreenOverlayLayout.ts"
import type { ScreenCameraOverlayPosition } from "./tradeRoomBroadcastScreenOverlayTypes.ts"
import { logBroadcast } from "./tradeRoomBroadcastDiagnostics.ts"

const MAX_CANVAS_LONG_EDGE = 1920
const COMPOSITE_FPS = 24

export type BroadcastScreenOverlayCompositorOptions = {
  screenTrack: MediaStreamTrack
  cameraTrack: MediaStreamTrack
  position: ScreenCameraOverlayPosition
  /** When false, only the screen is drawn (camera track may stay alive for fast re-enable). */
  showCamera: boolean
}

/**
 * Draws screen + optional webcam PiP into a canvas and exposes a single MediaStreamTrack for LiveKit.
 */
export class BroadcastScreenOverlayCompositor {
  private readonly screenTrack: MediaStreamTrack
  private cameraTrack: MediaStreamTrack | null
  private position: ScreenCameraOverlayPosition
  private showCamera: boolean

  private canvas: HTMLCanvasElement | null = null
  private ctx: CanvasRenderingContext2D | null = null
  private screenVideo: HTMLVideoElement | null = null
  private cameraVideo: HTMLVideoElement | null = null
  private outputStream: MediaStream | null = null
  private raf = 0
  private running = false

  constructor(options: BroadcastScreenOverlayCompositorOptions) {
    this.screenTrack = options.screenTrack
    this.cameraTrack = options.cameraTrack
    this.position = options.position
    this.showCamera = options.showCamera
  }

  setPosition(position: ScreenCameraOverlayPosition): void {
    this.position = position
  }

  setShowCamera(show: boolean): void {
    this.showCamera = show
  }

  setCameraTrack(track: MediaStreamTrack | null): void {
    if (this.cameraVideo) {
      this.cameraVideo.srcObject = null
    }
    this.cameraTrack = track
    if (this.cameraVideo && track) {
      this.cameraVideo.srcObject = new MediaStream([track])
      void this.cameraVideo.play().catch(() => {})
    }
  }

  async start(): Promise<MediaStreamTrack> {
    if (typeof document === "undefined") {
      throw new Error("Screen overlay compositor requires a browser DOM.")
    }
    if (this.running && this.outputStream) {
      const out = this.outputStream.getVideoTracks()[0]
      if (out) return out
    }

    this.canvas = document.createElement("canvas")
    this.ctx = this.canvas.getContext("2d", { alpha: false })
    if (!this.ctx) {
      throw new Error("Could not create overlay canvas context.")
    }

    this.screenVideo = document.createElement("video")
    this.screenVideo.muted = true
    this.screenVideo.playsInline = true
    this.screenVideo.srcObject = new MediaStream([this.screenTrack])

    this.cameraVideo = document.createElement("video")
    this.cameraVideo.muted = true
    this.cameraVideo.playsInline = true
    if (this.cameraTrack) {
      this.cameraVideo.srcObject = new MediaStream([this.cameraTrack])
    }

    await Promise.all([
      this.screenVideo.play().catch((err) => {
        logBroadcast("compositor screen video play failed", {
          message: err instanceof Error ? err.message : String(err),
        })
      }),
      this.cameraVideo.play().catch((err) => {
        logBroadcast("compositor camera video play failed", {
          message: err instanceof Error ? err.message : String(err),
        })
      }),
    ])

    await waitForVideoDimensions(this.screenVideo, "screen")
    if (this.cameraTrack) {
      await waitForVideoDimensions(this.cameraVideo!, "camera").catch(() => {})
    }

    const sw = this.screenVideo.videoWidth
    const sh = this.screenVideo.videoHeight
    const scale =
      Math.max(sw, sh) > MAX_CANVAS_LONG_EDGE
        ? MAX_CANVAS_LONG_EDGE / Math.max(sw, sh)
        : 1
    this.canvas.width = Math.max(2, Math.round(sw * scale))
    this.canvas.height = Math.max(2, Math.round(sh * scale))

    this.outputStream = this.canvas.captureStream(COMPOSITE_FPS)
    this.running = true
    const tick = () => {
      this.drawFrame()
      this.raf = requestAnimationFrame(tick)
    }
    this.raf = requestAnimationFrame(tick)

    const track = this.outputStream.getVideoTracks()[0]
    if (!track) {
      throw new Error("Composite captureStream did not produce a video track.")
    }
    logBroadcast("compositor captureStream created", {
      canvasWidth: this.canvas.width,
      canvasHeight: this.canvas.height,
      screenVideoWidth: this.screenVideo.videoWidth,
      screenVideoHeight: this.screenVideo.videoHeight,
      outputTrackId: track.id,
      outputReadyState: track.readyState,
    })
    return track
  }

  /** Paint a few frames so captureStream emits non-empty dimensions before publish. */
  async warmupFrames(count = 2): Promise<void> {
    for (let i = 0; i < count; i++) {
      this.drawFrame()
      await new Promise<void>((resolve) => {
        requestAnimationFrame(() => resolve())
      })
    }
  }

  getHealth(): Record<string, unknown> {
    const out = this.outputStream?.getVideoTracks()[0]
    return {
      canvasWidth: this.canvas?.width ?? 0,
      canvasHeight: this.canvas?.height ?? 0,
      screenReadyState: this.screenVideo?.readyState ?? null,
      screenVideoWidth: this.screenVideo?.videoWidth ?? 0,
      screenVideoHeight: this.screenVideo?.videoHeight ?? 0,
      cameraReadyState: this.cameraVideo?.readyState ?? null,
      cameraVideoWidth: this.cameraVideo?.videoWidth ?? 0,
      cameraVideoHeight: this.cameraVideo?.videoHeight ?? 0,
      outputReadyState: out?.readyState ?? null,
      outputEnabled: out?.enabled ?? null,
    }
  }

  stop(): void {
    this.running = false
    if (this.raf) {
      cancelAnimationFrame(this.raf)
      this.raf = 0
    }
    if (this.outputStream) {
      for (const t of this.outputStream.getTracks()) t.stop()
      this.outputStream = null
    }
    if (this.screenVideo) {
      this.screenVideo.srcObject = null
      this.screenVideo = null
    }
    if (this.cameraVideo) {
      this.cameraVideo.srcObject = null
      this.cameraVideo = null
    }
    this.canvas = null
    this.ctx = null
  }

  private drawFrame(): void {
    const ctx = this.ctx
    const canvas = this.canvas
    const screen = this.screenVideo
    if (!ctx || !canvas || !screen || screen.readyState < 2) return

    ctx.fillStyle = "#000"
    ctx.fillRect(0, 0, canvas.width, canvas.height)
    ctx.drawImage(screen, 0, 0, canvas.width, canvas.height)

    if (!this.showCamera || !this.cameraTrack || !this.cameraVideo) return
    const cam = this.cameraVideo
    if (cam.readyState < 2 || cam.videoWidth === 0) return

    const { width: pipW, height: pipH } = screenOverlayPipSize({
      canvasWidth: canvas.width,
      cameraWidth: cam.videoWidth,
      cameraHeight: cam.videoHeight,
    })
    const { x, y } = screenOverlayPipRect({
      canvasWidth: canvas.width,
      canvasHeight: canvas.height,
      pipWidth: pipW,
      pipHeight: pipH,
      position: this.position,
    })

    ctx.save()
    const r = SCREEN_OVERLAY_CORNER_RADIUS_PX
    roundRectPath(ctx, x, y, pipW, pipH, r)
    ctx.clip()
    ctx.drawImage(cam, x, y, pipW, pipH)
    ctx.restore()

    ctx.save()
    ctx.strokeStyle = "rgba(255,255,255,0.35)"
    ctx.lineWidth = 2
    roundRectPath(ctx, x, y, pipW, pipH, r)
    ctx.stroke()
    ctx.restore()
  }
}

function roundRectPath(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  r: number
): void {
  const radius = Math.min(r, w / 2, h / 2)
  ctx.beginPath()
  ctx.moveTo(x + radius, y)
  ctx.lineTo(x + w - radius, y)
  ctx.quadraticCurveTo(x + w, y, x + w, y + radius)
  ctx.lineTo(x + w, y + h - radius)
  ctx.quadraticCurveTo(x + w, y + h, x + w - radius, y + h)
  ctx.lineTo(x + radius, y + h)
  ctx.quadraticCurveTo(x, y + h, x, y + h - radius)
  ctx.lineTo(x, y + radius)
  ctx.quadraticCurveTo(x, y, x + radius, y)
  ctx.closePath()
}

async function waitForVideoDimensions(
  video: HTMLVideoElement,
  label: "screen" | "camera"
): Promise<void> {
  if (video.videoWidth > 0) return
  await new Promise<void>((resolve, reject) => {
    const to = window.setTimeout(
      () =>
        reject(
          new Error(
            `Timed out waiting for ${label} video dimensions (track may be black or ended).`
          )
        ),
      15_000
    )
    const done = () => {
      window.clearTimeout(to)
      resolve()
    }
    video.onloadedmetadata = () => {
      if (video.videoWidth > 0) done()
    }
    video.onresize = () => {
      if (video.videoWidth > 0) done()
    }
    if (video.videoWidth > 0) done()
  })
}
