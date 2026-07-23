"use client"

/**
 * Photos-style fullscreen media viewer for Capacitor iOS only.
 * Do not mount on web / Android — callers must gate with isNativeIos().
 */

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type CSSProperties,
  type PointerEvent as ReactPointerEvent,
  type SyntheticEvent,
} from "react"
import { createPortal } from "react-dom"
import { findMediaOriginRect } from "@/lib/findMediaOriginRect"
import { hapticLight } from "@/lib/nativeHaptics"
import {
  hideNativeIosMediaStatusBar,
  restoreNativeIosMediaStatusBar,
} from "@/lib/nativeIosMediaStatusBar"
import { toFullResolutionMediaUrl } from "@/lib/nativeIosMediaUrl"
import { useModalScrollLock } from "./modalLayout"

export type NativeIosMediaItem =
  | { type: "image"; url: string; alt?: string }
  | {
      type: "video"
      url: string
      poster?: string | null
      initialTime?: number
      startMuted?: boolean
    }

export type NativeIosMediaViewerProps = {
  open: boolean
  items: NativeIosMediaItem[]
  initialIndex?: number
  onClose: () => void
  /** Optional explicit origin; otherwise the matching on-screen thumbnail is found. */
  originRect?: DOMRect | null
  zIndexClass?: string
  /** Fired when a video item closes so callers can restore playback position. */
  onVideoTime?: (url: string, time: number) => void
}

const MIN_SCALE = 1
const MAX_SCALE = 4
const DOUBLE_TAP_ZOOM = 2.5
const DOUBLE_TAP_MS = 280
const DISMISS_DISTANCE = 96
const DISMISS_VELOCITY = 0.85
const PINCH_CLOSE_SCALE = 0.88
const PAGE_SWIPE_THRESHOLD = 64
const FRICTION = 0.92
const MIN_MOMENTUM = 0.05

type Transform = { scale: number; x: number; y: number }

type PointerSample = {
  id: number
  x: number
  y: number
}

function clamp(n: number, min: number, max: number) {
  return Math.min(max, Math.max(min, n))
}

function distance(a: PointerSample, b: PointerSample) {
  return Math.hypot(a.x - b.x, a.y - b.y)
}

function midpoint(a: PointerSample, b: PointerSample) {
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 }
}

function formatTime(seconds: number) {
  if (!Number.isFinite(seconds) || seconds < 0) return "0:00"
  const m = Math.floor(seconds / 60)
  const s = Math.floor(seconds % 60)
  return `${m}:${s.toString().padStart(2, "0")}`
}

function itemKey(item: NativeIosMediaItem, index: number) {
  return `${item.type}:${item.url}:${index}`
}

export default function NativeIosMediaViewer({
  open,
  items,
  initialIndex = 0,
  onClose,
  originRect = null,
  zIndexClass = "z-[10001]",
  onVideoTime,
}: NativeIosMediaViewerProps) {
  const [mounted, setMounted] = useState(false)
  const [index, setIndex] = useState(initialIndex)
  const [controlsVisible, setControlsVisible] = useState(true)
  const [entering, setEntering] = useState(true)
  const [dismissing, setDismissing] = useState(false)
  const [bgOpacity, setBgOpacity] = useState(1)
  const [pageOffset, setPageOffset] = useState(0)
  const [interacting, setInteracting] = useState(false)

  const transformRef = useRef<Transform>({ scale: 1, x: 0, y: 0 })
  const [transform, setTransform] = useState<Transform>({
    scale: 1,
    x: 0,
    y: 0,
  })
  const zoomByIndexRef = useRef<Map<number, Transform>>(new Map())

  const stageRef = useRef<HTMLDivElement>(null)
  const mediaRef = useRef<HTMLDivElement>(null)
  const videoRef = useRef<HTMLVideoElement>(null)
  const pointersRef = useRef<Map<number, PointerSample>>(new Map())
  const pinchStartRef = useRef<{
    distance: number
    scale: number
    mid: { x: number; y: number }
    transform: Transform
  } | null>(null)
  const panStartRef = useRef<{
    x: number
    y: number
    transform: Transform
    mode: "pan" | "dismiss" | "page" | "undecided"
  } | null>(null)
  const lastTapRef = useRef<{ t: number; x: number; y: number } | null>(null)
  const suppressTapToggleRef = useRef(false)
  const [origin, setOrigin] = useState<DOMRect | null>(null)
  const velocityRef = useRef({ x: 0, y: 0, t: 0 })
  const momentumRafRef = useRef<number | null>(null)
  const dismissProgressRef = useRef(0)
  const closedVideoTimeRef = useRef(0)

  const [videoPlaying, setVideoPlaying] = useState(false)
  const [videoMuted, setVideoMuted] = useState(true)
  const [videoTime, setVideoTime] = useState(0)
  const [videoDuration, setVideoDuration] = useState(0)
  const [scrubbing, setScrubbing] = useState(false)

  const safeItems = items.filter((item) => Boolean(item.url?.trim()))
  const active = safeItems[clamp(index, 0, Math.max(0, safeItems.length - 1))]
  const show = open && mounted && safeItems.length > 0 && Boolean(active)

  useEffect(() => {
    setMounted(true)
  }, [])

  useModalScrollLock(show)

  const applyTransform = useCallback((next: Transform) => {
    transformRef.current = next
    setTransform(next)
  }, [])

  const resetTransform = useCallback(() => {
    applyTransform({ scale: 1, x: 0, y: 0 })
  }, [applyTransform])

  const persistZoomForIndex = useCallback(
    (i: number) => {
      zoomByIndexRef.current.set(i, { ...transformRef.current })
    },
    []
  )

  const restoreZoomForIndex = useCallback(
    (i: number) => {
      const saved = zoomByIndexRef.current.get(i)
      applyTransform(saved ?? { scale: 1, x: 0, y: 0 })
    },
    [applyTransform]
  )

  const goToIndex = useCallback(
    (nextIndex: number) => {
      const clamped = clamp(nextIndex, 0, safeItems.length - 1)
      if (clamped === index) {
        setPageOffset(0)
        return
      }
      persistZoomForIndex(index)
      setIndex(clamped)
      restoreZoomForIndex(clamped)
      setPageOffset(0)
      setControlsVisible(true)
    },
    [index, persistZoomForIndex, restoreZoomForIndex, safeItems.length]
  )

  // Open / close lifecycle: status bar, origin FLIP, index reset.
  useEffect(() => {
    if (!open || !mounted || safeItems.length === 0) return

    const start = clamp(initialIndex, 0, safeItems.length - 1)
    setIndex(start)
    zoomByIndexRef.current.clear()
    applyTransform({ scale: 1, x: 0, y: 0 })
    setPageOffset(0)
    setBgOpacity(1)
    setDismissing(false)
    setEntering(true)
    setControlsVisible(true)
    dismissProgressRef.current = 0

    const first = safeItems[start]!
    const rect =
      originRect ??
      findMediaOriginRect(
        first.type === "video" ? first.poster || first.url : first.url
      )
    setOrigin(rect)

    void hideNativeIosMediaStatusBar()

    // Double rAF: paint at thumbnail transform, then animate to fullscreen.
    let frame2 = 0
    const frame1 = requestAnimationFrame(() => {
      frame2 = requestAnimationFrame(() => setEntering(false))
    })

    return () => {
      cancelAnimationFrame(frame1)
      cancelAnimationFrame(frame2)
      void restoreNativeIosMediaStatusBar()
    }
    // Only re-run when the viewer opens/closes, not on every index change.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, mounted])

  // Video item setup when the active slide changes.
  useEffect(() => {
    if (!show || !active || active.type !== "video") {
      setVideoPlaying(false)
      return
    }

    const video = videoRef.current
    if (!video) return

    const startMuted = active.startMuted ?? true
    const startTime = active.initialTime ?? 0
    setVideoMuted(startMuted)
    video.muted = startMuted
    const applyStart = () => {
      if (startTime > 0 && Number.isFinite(startTime)) {
        try {
          video.currentTime = startTime
        } catch {
          // Ignore seek before metadata.
        }
      }
      void video.play().then(
        () => setVideoPlaying(true),
        () => setVideoPlaying(false)
      )
    }

    if (video.readyState >= 1) applyStart()
    else {
      const onMeta = () => {
        video.removeEventListener("loadedmetadata", onMeta)
        applyStart()
      }
      video.addEventListener("loadedmetadata", onMeta)
      return () => video.removeEventListener("loadedmetadata", onMeta)
    }
  }, [show, active, index])

  useEffect(() => {
    if (!show) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.preventDefault()
        e.stopPropagation()
        beginDismiss()
      } else if (e.key === "ArrowRight") {
        goToIndex(index + 1)
      } else if (e.key === "ArrowLeft") {
        goToIndex(index - 1)
      }
    }
    window.addEventListener("keydown", onKey, true)
    return () => window.removeEventListener("keydown", onKey, true)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [show, index, goToIndex])

  const reportVideoTime = useCallback(() => {
    if (!active || active.type !== "video") return
    const t = videoRef.current?.currentTime ?? closedVideoTimeRef.current
    onVideoTime?.(active.url, t)
  }, [active, onVideoTime])

  const finishClose = useCallback(() => {
    reportVideoTime()
    videoRef.current?.pause()
    onClose()
  }, [onClose, reportVideoTime])

  const beginDismiss = useCallback(() => {
    if (dismissing) return
    setInteracting(false)
    setDismissing(true)
    setControlsVisible(false)
    setBgOpacity(0)
    hapticLight("media-dismiss")
    reportVideoTime()
    videoRef.current?.pause()
    window.setTimeout(() => {
      finishClose()
    }, 280)
  }, [dismissing, finishClose, reportVideoTime])

  const stopMomentum = useCallback(() => {
    if (momentumRafRef.current != null) {
      cancelAnimationFrame(momentumRafRef.current)
      momentumRafRef.current = null
    }
  }, [])

  const clampPan = useCallback((next: Transform): Transform => {
    const stage = stageRef.current
    const media = mediaRef.current
    if (!stage || !media || next.scale <= 1.01) {
      return { scale: Math.max(MIN_SCALE, next.scale), x: 0, y: 0 }
    }
    const stageRect = stage.getBoundingClientRect()
    const mediaRect = media.getBoundingClientRect()
    // Approximate overflow from untransformed size * scale.
    const baseW = mediaRect.width / transformRef.current.scale || mediaRect.width
    const baseH = mediaRect.height / transformRef.current.scale || mediaRect.height
    const scaledW = baseW * next.scale
    const scaledH = baseH * next.scale
    const maxX = Math.max(0, (scaledW - stageRect.width) / 2)
    const maxY = Math.max(0, (scaledH - stageRect.height) / 2)
    return {
      scale: clamp(next.scale, MIN_SCALE, MAX_SCALE),
      x: clamp(next.x, -maxX, maxX),
      y: clamp(next.y, -maxY, maxY),
    }
  }, [])

  const runMomentum = useCallback(() => {
    stopMomentum()
    const step = () => {
      const v = velocityRef.current
      if (Math.abs(v.x) < MIN_MOMENTUM && Math.abs(v.y) < MIN_MOMENTUM) {
        momentumRafRef.current = null
        applyTransform(clampPan(transformRef.current))
        return
      }
      const next = clampPan({
        ...transformRef.current,
        x: transformRef.current.x + v.x,
        y: transformRef.current.y + v.y,
      })
      applyTransform(next)
      velocityRef.current = { x: v.x * FRICTION, y: v.y * FRICTION, t: performance.now() }
      momentumRafRef.current = requestAnimationFrame(step)
    }
    momentumRafRef.current = requestAnimationFrame(step)
  }, [applyTransform, clampPan, stopMomentum])

  const zoomTo = useCallback(
    (targetScale: number, clientX: number, clientY: number) => {
      const stage = stageRef.current
      if (!stage) {
        applyTransform({ scale: targetScale, x: 0, y: 0 })
        return
      }
      const rect = stage.getBoundingClientRect()
      const cx = clientX - rect.left - rect.width / 2
      const cy = clientY - rect.top - rect.height / 2
      const current = transformRef.current
      if (targetScale <= 1.01) {
        applyTransform({ scale: 1, x: 0, y: 0 })
        return
      }
      const ratio = targetScale / current.scale
      applyTransform(
        clampPan({
          scale: targetScale,
          x: cx - (cx - current.x) * ratio,
          y: cy - (cy - current.y) * ratio,
        })
      )
    },
    [applyTransform, clampPan]
  )

  const handleDoubleTap = useCallback(
    (clientX: number, clientY: number) => {
      const current = transformRef.current.scale
      if (current > 1.05) {
        zoomTo(1, clientX, clientY)
      } else {
        zoomTo(DOUBLE_TAP_ZOOM, clientX, clientY)
        hapticLight("media-zoom")
      }
    },
    [zoomTo]
  )

  const onPointerDown = (e: ReactPointerEvent) => {
    if (dismissing || entering) return
    stopMomentum()
    setInteracting(true)
    ;(e.target as HTMLElement).setPointerCapture?.(e.pointerId)
    pointersRef.current.set(e.pointerId, { id: e.pointerId, x: e.clientX, y: e.clientY })

    if (pointersRef.current.size === 2) {
      const [a, b] = Array.from(pointersRef.current.values())
      if (!a || !b) return
      pinchStartRef.current = {
        distance: distance(a, b),
        scale: transformRef.current.scale,
        mid: midpoint(a, b),
        transform: { ...transformRef.current },
      }
      panStartRef.current = null
      return
    }

    if (pointersRef.current.size === 1) {
      const now = performance.now()
      const last = lastTapRef.current
      if (
        last &&
        now - last.t < DOUBLE_TAP_MS &&
        Math.hypot(e.clientX - last.x, e.clientY - last.y) < 28 &&
        active?.type === "image"
      ) {
        lastTapRef.current = null
        suppressTapToggleRef.current = true
        handleDoubleTap(e.clientX, e.clientY)
        pointersRef.current.delete(e.pointerId)
        setInteracting(false)
        return
      }
      lastTapRef.current = { t: now, x: e.clientX, y: e.clientY }

      panStartRef.current = {
        x: e.clientX,
        y: e.clientY,
        transform: { ...transformRef.current },
        mode: transformRef.current.scale > 1.01 ? "pan" : "undecided",
      }
      velocityRef.current = { x: 0, y: 0, t: now }
    }
  }

  const onPointerMove = (e: ReactPointerEvent) => {
    if (!pointersRef.current.has(e.pointerId)) return
    pointersRef.current.set(e.pointerId, { id: e.pointerId, x: e.clientX, y: e.clientY })

    if (pointersRef.current.size >= 2 && pinchStartRef.current) {
      const [a, b] = Array.from(pointersRef.current.values())
      if (!a || !b) return
      const start = pinchStartRef.current
      const dist = distance(a, b)
      const mid = midpoint(a, b)
      const nextScale = clamp(
        start.scale * (dist / Math.max(1, start.distance)),
        0.75,
        MAX_SCALE
      )
      const stage = stageRef.current?.getBoundingClientRect()
      if (!stage) return
      const cx = mid.x - stage.left - stage.width / 2
      const cy = mid.y - stage.top - stage.height / 2
      const ratio = nextScale / start.transform.scale
      const next = {
        scale: nextScale,
        x: cx - (cx - start.transform.x) * ratio,
        y: cy - (cy - start.transform.y) * ratio,
      }
      if (nextScale >= 1) {
        applyTransform(clampPan(next))
        setBgOpacity(1)
        dismissProgressRef.current = 0
      } else {
        applyTransform(next)
        const progress = clamp((1 - nextScale) / (1 - PINCH_CLOSE_SCALE), 0, 1)
        dismissProgressRef.current = progress
        setBgOpacity(1 - progress * 0.85)
      }
      return
    }

    const pan = panStartRef.current
    if (!pan || pointersRef.current.size !== 1) return

    const dx = e.clientX - pan.x
    const dy = e.clientY - pan.y
    const now = performance.now()
    const dt = Math.max(1, now - velocityRef.current.t)

    if (pan.mode === "undecided") {
      if (Math.hypot(dx, dy) < 10) return
      if (transformRef.current.scale > 1.01) {
        pan.mode = "pan"
      } else if (Math.abs(dy) > Math.abs(dx) * 1.15) {
        pan.mode = "dismiss"
      } else if (safeItems.length > 1 && Math.abs(dx) > Math.abs(dy) * 1.1) {
        pan.mode = "page"
      } else {
        pan.mode = "dismiss"
      }
    }

    if (pan.mode === "pan") {
      const next = clampPan({
        scale: pan.transform.scale,
        x: pan.transform.x + dx,
        y: pan.transform.y + dy,
      })
      const prev = transformRef.current
      velocityRef.current = {
        x: ((next.x - prev.x) / dt) * 16,
        y: ((next.y - prev.y) / dt) * 16,
        t: now,
      }
      applyTransform(next)
      return
    }

    if (pan.mode === "dismiss") {
      const progress = clamp(Math.abs(dy) / 280, 0, 1)
      dismissProgressRef.current = progress
      setBgOpacity(1 - progress * 0.75)
      applyTransform({ scale: 1 - progress * 0.12, x: dx * 0.35, y: dy })
      velocityRef.current = { x: dx / dt, y: dy / dt, t: now }
      return
    }

    if (pan.mode === "page") {
      setPageOffset(dx)
      setBgOpacity(1)
      velocityRef.current = { x: dx / dt, y: 0, t: now }
    }
  }

  const onPointerUp = (e: ReactPointerEvent) => {
    pointersRef.current.delete(e.pointerId)

    if (pointersRef.current.size < 2) {
      const pinch = pinchStartRef.current
      pinchStartRef.current = null
      if (pinch && transformRef.current.scale < PINCH_CLOSE_SCALE) {
        beginDismiss()
        return
      }
      if (transformRef.current.scale < 1) {
        applyTransform({ scale: 1, x: 0, y: 0 })
        setBgOpacity(1)
        dismissProgressRef.current = 0
      } else {
        applyTransform(clampPan(transformRef.current))
      }
    }

    if (pointersRef.current.size === 0) {
      setInteracting(false)
      const pan = panStartRef.current
      panStartRef.current = null
      if (!pan) return

      if (pan.mode === "dismiss") {
        const dy = transformRef.current.y
        const vy = velocityRef.current.y
        if (Math.abs(dy) > DISMISS_DISTANCE || Math.abs(vy) > DISMISS_VELOCITY) {
          beginDismiss()
          return
        }
        applyTransform({ scale: 1, x: 0, y: 0 })
        setBgOpacity(1)
        dismissProgressRef.current = 0
        return
      }

      if (pan.mode === "page") {
        const dx = pageOffset
        if (dx < -PAGE_SWIPE_THRESHOLD && index < safeItems.length - 1) {
          goToIndex(index + 1)
        } else if (dx > PAGE_SWIPE_THRESHOLD && index > 0) {
          goToIndex(index - 1)
        } else {
          setPageOffset(0)
        }
        return
      }

      if (pan.mode === "pan" && transformRef.current.scale > 1.01) {
        runMomentum()
        return
      }

      // Tap (minimal movement) toggles controls.
      if (pan.mode === "undecided") {
        if (suppressTapToggleRef.current) {
          suppressTapToggleRef.current = false
          return
        }
        setControlsVisible((v) => !v)
      }
    }
  }

  const togglePlay = useCallback(() => {
    const video = videoRef.current
    if (!video) return
    if (video.paused) {
      void video.play().then(
        () => setVideoPlaying(true),
        () => setVideoPlaying(false)
      )
    } else {
      video.pause()
      setVideoPlaying(false)
    }
  }, [])

  const toggleMute = useCallback(() => {
    const video = videoRef.current
    if (!video) return
    const next = !video.muted
    video.muted = next
    setVideoMuted(next)
  }, [])

  const openAirPlay = useCallback(() => {
    const video = videoRef.current as HTMLVideoElement & {
      webkitShowPlaybackTargetPicker?: () => void
    }
    if (!video) return
    try {
      video.webkitShowPlaybackTargetPicker?.()
    } catch {
      // AirPlay picker unavailable.
    }
  }, [])

  const openPiP = useCallback(async () => {
    const video = videoRef.current as HTMLVideoElement & {
      webkitSetPresentationMode?: (mode: string) => void
      webkitSupportsPresentationMode?: (mode: string) => boolean
    }
    if (!video) return
    try {
      if (
        typeof video.webkitSetPresentationMode === "function" &&
        video.webkitSupportsPresentationMode?.("picture-in-picture")
      ) {
        video.webkitSetPresentationMode("picture-in-picture")
        return
      }
      if (document.pictureInPictureEnabled && !video.disablePictureInPicture) {
        if (document.pictureInPictureElement === video) {
          await document.exitPictureInPicture()
        } else {
          await video.requestPictureInPicture()
        }
      }
    } catch {
      // PiP unsupported / denied.
    }
  }, [])

  const onVideoTimeUpdate = () => {
    const video = videoRef.current
    if (!video || scrubbing) return
    closedVideoTimeRef.current = video.currentTime
    setVideoTime(video.currentTime)
    if (Number.isFinite(video.duration)) setVideoDuration(video.duration)
  }

  const onScrub = (value: number) => {
    const video = videoRef.current
    if (!video) return
    video.currentTime = value
    closedVideoTimeRef.current = value
    setVideoTime(value)
  }

  // Adjacent image preload only.
  useEffect(() => {
    if (!show) return
    const urls: string[] = []
    for (const offset of [-1, 1]) {
      const item = safeItems[index + offset]
      if (item?.type === "image") {
        urls.push(toFullResolutionMediaUrl(item.url))
      }
    }
    const loaders = urls.map((url) => {
      const img = new Image()
      img.decoding = "async"
      img.src = url
      return img
    })
    return () => {
      for (const img of loaders) {
        img.src = ""
      }
    }
  }, [show, index, safeItems])

  // Release media on dismiss.
  useEffect(() => {
    if (show) return
    const video = videoRef.current
    if (video) {
      video.pause()
      video.removeAttribute("src")
      video.load()
    }
  }, [show])

  if (!show || !active) return null

  const stageStyle: CSSProperties = {
    transform: `translate3d(calc(${pageOffset}px + ${transform.x}px), ${transform.y}px, 0) scale(${transform.scale})`,
    transition:
      interacting
        ? "none"
        : dismissing || entering
          ? "transform 280ms cubic-bezier(0.32, 0.72, 0, 1), opacity 280ms ease"
          : "transform 220ms cubic-bezier(0.32, 0.72, 0, 1)",
    opacity: dismissing ? 0.35 : 1,
    transformOrigin: "center center",
  }

  if ((entering || dismissing) && origin) {
    const vw = typeof window !== "undefined" ? window.innerWidth : 390
    const vh = typeof window !== "undefined" ? window.innerHeight : 844
    const scaleX = origin.width / vw
    const scaleY = origin.height / vh
    const startScale = Math.max(scaleX, scaleY)
    const originCx = origin.left + origin.width / 2
    const originCy = origin.top + origin.height / 2
    const dx = originCx - vw / 2
    const dy = originCy - vh / 2
    if (entering) {
      stageStyle.transform = `translate3d(${dx}px, ${dy}px, 0) scale(${startScale})`
      stageStyle.opacity = 1
      stageStyle.transition = "none"
    } else if (dismissing) {
      stageStyle.transform = `translate3d(${dx}px, ${dy}px, 0) scale(${startScale})`
      stageStyle.opacity = 0.9
    }
  }

  const fullUrl =
    active.type === "image"
      ? toFullResolutionMediaUrl(active.url)
      : active.url

  return createPortal(
    <div
      className={`fixed inset-0 ${zIndexClass} touch-none overscroll-none`}
      role="dialog"
      aria-modal="true"
      aria-label="Media viewer"
      style={{ backgroundColor: `rgba(0,0,0,${bgOpacity})` }}
    >
      <div
        ref={stageRef}
        className="absolute inset-0 flex items-center justify-center overflow-hidden"
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        onPointerLeave={(e) => {
          if (pointersRef.current.has(e.pointerId)) onPointerUp(e)
        }}
      >
        <div ref={mediaRef} className="relative max-h-full max-w-full" style={stageStyle}>
          {active.type === "image" ? (
            // eslint-disable-next-line @next/next/no-img-element -- exact bytes for zoom viewer
            <img
              src={fullUrl}
              alt={active.alt ?? ""}
              draggable={false}
              decoding="async"
              className="max-h-[100dvh] max-w-[100vw] select-none object-contain"
              style={{ WebkitUserSelect: "none", userSelect: "none" }}
            />
          ) : (
            <video
              ref={videoRef}
              src={fullUrl}
              poster={active.poster ?? undefined}
              className="max-h-[100dvh] max-w-[100vw] select-none object-contain"
              playsInline
              // WebKit AirPlay (iOS WKWebView)
              {...{ "x-webkit-airplay": "allow" }}
              disablePictureInPicture={false}
              preload="auto"
              muted={videoMuted}
              onPlay={() => setVideoPlaying(true)}
              onPause={() => setVideoPlaying(false)}
              onTimeUpdate={onVideoTimeUpdate}
              onLoadedMetadata={(e: SyntheticEvent<HTMLVideoElement>) => {
                setVideoDuration(e.currentTarget.duration || 0)
              }}
              onClick={(ev) => {
                ev.stopPropagation()
                setControlsVisible((v) => !v)
              }}
            />
          )}
        </div>
      </div>

      {/* Top controls */}
      <div
        className={`pointer-events-none absolute inset-x-0 top-0 z-10 flex items-start justify-between px-3 transition-opacity duration-200 ${
          controlsVisible && !dismissing ? "opacity-100" : "opacity-0"
        }`}
        style={{
          paddingTop: "max(0.75rem, env(safe-area-inset-top, 0px))",
        }}
      >
        <div className="pointer-events-auto">
          <button
            type="button"
            onClick={beginDismiss}
            className="flex h-11 w-11 items-center justify-center rounded-full bg-black/45 text-2xl leading-none text-white backdrop-blur-sm"
            aria-label="Close"
          >
            ×
          </button>
        </div>
        {safeItems.length > 1 ? (
          <div className="pointer-events-none rounded-full bg-black/45 px-3 py-1.5 text-sm font-medium text-white backdrop-blur-sm">
            {index + 1} / {safeItems.length}
          </div>
        ) : (
          <div />
        )}
      </div>

      {/* Page dots */}
      {safeItems.length > 1 && safeItems.length <= 12 ? (
        <div
          className={`pointer-events-none absolute inset-x-0 z-10 flex justify-center gap-1.5 transition-opacity duration-200 ${
            controlsVisible && !dismissing ? "opacity-100" : "opacity-0"
          }`}
          style={{
            bottom: "max(1.25rem, calc(env(safe-area-inset-bottom, 0px) + 0.75rem))",
          }}
        >
          {safeItems.map((item, i) => (
            <span
              key={itemKey(item, i)}
              className={`h-1.5 w-1.5 rounded-full ${
                i === index ? "bg-white" : "bg-white/35"
              }`}
            />
          ))}
        </div>
      ) : null}

      {/* Video controls */}
      {active.type === "video" ? (
        <div
          className={`absolute inset-x-0 z-10 px-4 transition-opacity duration-200 ${
            controlsVisible && !dismissing
              ? "pointer-events-auto opacity-100"
              : "pointer-events-none opacity-0"
          }`}
          style={{
            bottom: "max(1rem, calc(env(safe-area-inset-bottom, 0px) + 0.5rem))",
          }}
        >
          <div className="mx-auto max-w-lg rounded-2xl bg-black/55 px-3 py-3 backdrop-blur-md">
            <input
              type="range"
              min={0}
              max={videoDuration || 0}
              step={0.05}
              value={clamp(videoTime, 0, videoDuration || 0)}
              aria-label="Seek"
              className="mb-2 h-1.5 w-full cursor-pointer appearance-none rounded-full bg-white/25 accent-white"
              onPointerDown={() => setScrubbing(true)}
              onPointerUp={() => setScrubbing(false)}
              onChange={(e) => onScrub(Number(e.target.value))}
            />
            <div className="mb-2 flex justify-between text-[11px] tabular-nums text-white/80">
              <span>{formatTime(videoTime)}</span>
              <span>{formatTime(videoDuration)}</span>
            </div>
            <div className="flex items-center justify-center gap-3">
              <button
                type="button"
                onClick={togglePlay}
                className="flex h-11 min-w-11 items-center justify-center rounded-full bg-white/15 px-3 text-sm font-semibold text-white"
                aria-label={videoPlaying ? "Pause" : "Play"}
              >
                {videoPlaying ? "Pause" : "Play"}
              </button>
              <button
                type="button"
                onClick={toggleMute}
                className="flex h-11 min-w-11 items-center justify-center rounded-full bg-white/15 px-3 text-sm font-semibold text-white"
                aria-label={videoMuted ? "Unmute" : "Mute"}
              >
                {videoMuted ? "Unmute" : "Mute"}
              </button>
              <button
                type="button"
                onClick={openAirPlay}
                className="flex h-11 min-w-11 items-center justify-center rounded-full bg-white/15 px-3 text-sm font-semibold text-white"
                aria-label="AirPlay"
              >
                AirPlay
              </button>
              <button
                type="button"
                onClick={() => void openPiP()}
                className="flex h-11 min-w-11 items-center justify-center rounded-full bg-white/15 px-3 text-sm font-semibold text-white"
                aria-label="Picture in Picture"
              >
                PiP
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>,
    document.body
  )
}
