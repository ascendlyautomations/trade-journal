"use client"

import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
  type WheelEvent as ReactWheelEvent,
} from "react"
import {
  clampNormalizedCenter,
  STORY_TEXT_HIT_PADDING,
  STORY_TEXT_MIN_HIT,
  storyTextFillCss,
  storyTextMaxWidth,
  type StoryTextOverlay,
} from "@/lib/storyEditor/storyTextOverlay"
import {
  measureStoryText,
  storyOverlayFontSize,
} from "@/lib/storyEditor/storyTextMetrics"

type StoryTextOverlayNodeProps = {
  overlay: StoryTextOverlay
  canvasSize: { width: number; height: number }
  isSelected: boolean
  /** Selected layer while the text chrome / draft field is open. */
  isEditingActive?: boolean
  transformsEnabled: boolean
  onSelect: () => void
  onMove: (normalizedCenter: { x: number; y: number }) => void
  onScale: (scale: number) => void
  onRotation: (rotationRadians: number) => void
  onEdit: () => void
  onDragBegan?: () => void
  onDragLocation?: (canvasCenter: { x: number; y: number }) => void
  onDragEnded?: (canvasCenter: { x: number; y: number }) => void
}

export default function StoryTextOverlayNode({
  overlay,
  canvasSize,
  isSelected,
  isEditingActive = false,
  transformsEnabled,
  onSelect,
  onMove,
  onScale,
  onRotation,
  onEdit,
  onDragBegan,
  onDragLocation,
  onDragEnded,
}: StoryTextOverlayNodeProps) {
  const dragStartRef = useRef<{ x: number; y: number } | null>(null)
  const pointerOriginRef = useRef<{ x: number; y: number } | null>(null)
  const scaleStartRef = useRef<number | null>(null)
  const rotationStartRef = useRef<number | null>(null)
  const pinchStartRef = useRef<{
    distance: number
    scale: number
    angle: number
    rotation: number
  } | null>(null)
  const pointersRef = useRef<Map<number, { x: number; y: number }>>(new Map())
  const lastCenterRef = useRef(overlay.normalizedCenter)
  const [measured, setMeasured] = useState({ width: 0, height: 0 })

  useEffect(() => {
    lastCenterRef.current = overlay.normalizedCenter
  }, [overlay.normalizedCenter])

  useEffect(() => {
    setMeasured(measureStoryText(overlay, canvasSize.width))
  }, [overlay, canvasSize.width])

  const hitSize = useMemo(() => {
    const padded = {
      width: measured.width + STORY_TEXT_HIT_PADDING * 2,
      height: measured.height + STORY_TEXT_HIT_PADDING * 2,
    }
    return {
      width: Math.max(padded.width, STORY_TEXT_MIN_HIT.width),
      height: Math.max(padded.height, STORY_TEXT_MIN_HIT.height),
    }
  }, [measured.height, measured.width])

  const centerPx = useMemo(
    () => ({
      x: overlay.normalizedCenter.x * canvasSize.width,
      y: overlay.normalizedCenter.y * canvasSize.height,
    }),
    [
      canvasSize.height,
      canvasSize.width,
      overlay.normalizedCenter.x,
      overlay.normalizedCenter.y,
    ]
  )

  const fontSize = storyOverlayFontSize(canvasSize.width, overlay.scale)
  const maxTextWidth = storyTextMaxWidth(canvasSize.width)
  const textAlignClass =
    overlay.alignment === "leading"
      ? "text-left"
      : overlay.alignment === "trailing"
        ? "text-right"
        : "text-center"

  const clampCenter = useCallback(
    (center: { x: number; y: number }) =>
      clampNormalizedCenter(center, canvasSize, hitSize),
    [canvasSize, hitSize]
  )

  const toCanvasPoint = useCallback(
    (normalized: { x: number; y: number }) => ({
      x: normalized.x * canvasSize.width,
      y: normalized.y * canvasSize.height,
    }),
    [canvasSize.height, canvasSize.width]
  )

  const dragMovedRef = useRef(false)

  const onPointerDown = (e: ReactPointerEvent) => {
    if (!transformsEnabled) return
    e.stopPropagation()
    e.preventDefault()
    dragMovedRef.current = false
    onSelect()
    ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
    pointersRef.current.set(e.pointerId, { x: e.clientX, y: e.clientY })

    if (pointersRef.current.size === 1) {
      dragStartRef.current = { ...overlay.normalizedCenter }
      pointerOriginRef.current = { x: e.clientX, y: e.clientY }
      onDragBegan?.()
    } else if (pointersRef.current.size === 2 && isSelected) {
      const pts = [...pointersRef.current.values()]
      pinchStartRef.current = {
        distance: hypot(pts[0], pts[1]),
        scale: overlay.scale,
        angle: Math.atan2(pts[1].y - pts[0].y, pts[1].x - pts[0].x),
        rotation: overlay.rotationRadians,
      }
      dragStartRef.current = null
      pointerOriginRef.current = null
    }
  }

  const onPointerMove = (e: ReactPointerEvent) => {
    if (!transformsEnabled) return
    if (!pointersRef.current.has(e.pointerId)) return
    e.preventDefault()
    pointersRef.current.set(e.pointerId, { x: e.clientX, y: e.clientY })

    if (pointersRef.current.size >= 2 && isSelected && pinchStartRef.current) {
      const pts = [...pointersRef.current.values()]
      const distance = hypot(pts[0], pts[1])
      const angle = Math.atan2(pts[1].y - pts[0].y, pts[1].x - pts[0].x)
      const start = pinchStartRef.current
      if (start.distance > 0) {
        onScale(start.scale * (distance / start.distance))
      }
      onRotation(start.rotation + (angle - start.angle))
      return
    }

    if (
      pointersRef.current.size === 1 &&
      dragStartRef.current &&
      pointerOriginRef.current
    ) {
      const start = dragStartRef.current
      const origin = pointerOriginRef.current
      const dx = (e.clientX - origin.x) / Math.max(canvasSize.width, 1)
      const dy = (e.clientY - origin.y) / Math.max(canvasSize.height, 1)
      const next = clampCenter({ x: start.x + dx, y: start.y + dy })
      lastCenterRef.current = next
      if (
        !dragMovedRef.current &&
        (Math.abs(e.clientX - (pointerOriginRef.current?.x ?? 0)) >= 4 ||
          Math.abs(e.clientY - (pointerOriginRef.current?.y ?? 0)) >= 4)
      ) {
        dragMovedRef.current = true
        blurStoryDraftField()
      }
      onMove(next)
      onDragLocation?.(toCanvasPoint(next))
    }
  }

  const onPointerUp = (e: ReactPointerEvent) => {
    pointersRef.current.delete(e.pointerId)
    if (pointersRef.current.size < 2) pinchStartRef.current = null

    if (pointersRef.current.size === 0) {
      const origin = pointerOriginRef.current
      const moved =
        origin != null &&
        (Math.abs(e.clientX - origin.x) >= 4 || Math.abs(e.clientY - origin.y) >= 4)
      if (moved) {
        onDragEnded?.(toCanvasPoint(lastCenterRef.current))
      } else if (!moved) {
        onSelect()
      }
      dragStartRef.current = null
      pointerOriginRef.current = null
      if (isEditingActive && dragMovedRef.current) {
        refocusStoryDraftField()
      }
      dragMovedRef.current = false
    }
  }

  const onWheel = (e: ReactWheelEvent) => {
    if (!transformsEnabled || !isSelected) return
    if (e.ctrlKey || e.metaKey) {
      e.preventDefault()
      if (scaleStartRef.current == null) scaleStartRef.current = overlay.scale
      const factor = Math.exp(-e.deltaY * 0.01)
      onScale((scaleStartRef.current ?? overlay.scale) * factor)
    } else if (e.shiftKey) {
      e.preventDefault()
      if (rotationStartRef.current == null) {
        rotationStartRef.current = overlay.rotationRadians
      }
      onRotation(
        (rotationStartRef.current ?? overlay.rotationRadians) + e.deltaY * 0.01
      )
    }
  }

  const onWheelEnd = () => {
    scaleStartRef.current = null
    rotationStartRef.current = null
  }

  return (
    <div
      className="absolute z-10 touch-none select-none"
      style={{
        left: centerPx.x,
        top: centerPx.y,
        width: hitSize.width,
        height: hitSize.height,
        transform: `translate(-50%, -50%) rotate(${overlay.rotationRadians}rad)`,
      }}
      onClick={(e) => e.stopPropagation()}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerUp}
      onWheel={onWheel}
      onWheelCapture={onWheelEnd}
      onDoubleClick={(ev) => {
        ev.stopPropagation()
        onEdit()
      }}
    >
      <div
        className={`relative flex h-full w-full flex-col items-center justify-center ${
          isSelected && transformsEnabled
            ? "rounded-[10px] ring-2 ring-emerald-400/80"
            : ""
        }`}
      >
        {isEditingActive ? (
          <div
            className="absolute left-1/2 top-1 flex -translate-x-1/2 cursor-grab items-center gap-0.5 rounded-full border border-white/25 bg-black/50 px-2 py-0.5 active:cursor-grabbing"
            aria-hidden
          >
            <span className="h-0.5 w-3 rounded-full bg-white/70" />
            <span className="h-0.5 w-3 rounded-full bg-white/70" />
          </div>
        ) : null}
        <p
          className={`pointer-events-none whitespace-pre-wrap font-semibold leading-snug ${textAlignClass}`}
          style={{
            fontSize,
            maxWidth: maxTextWidth,
            color: storyTextFillCss(overlay.textFill),
            padding: overlay.showsBackground ? 8 : 0,
            borderRadius: overlay.showsBackground ? 8 : undefined,
            backgroundColor: overlay.showsBackground
              ? "rgba(0, 0, 0, 0.45)"
              : undefined,
          }}
        >
          {overlay.text.trim() ? overlay.text : " "}
        </p>
      </div>
    </div>
  )
}

function hypot(
  a: { x: number; y: number },
  b: { x: number; y: number }
): number {
  return Math.hypot(b.x - a.x, b.y - a.y)
}

function blurStoryDraftField() {
  const active = document.activeElement
  if (
    active instanceof HTMLTextAreaElement &&
    active.dataset.storyTextDraft === "true"
  ) {
    active.blur()
  }
}

function refocusStoryDraftField() {
  const field = document.querySelector<HTMLTextAreaElement>(
    'textarea[data-story-text-draft="true"]'
  )
  field?.focus({ preventScroll: true })
}
