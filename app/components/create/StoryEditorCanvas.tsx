"use client"

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
  type WheelEvent as ReactWheelEvent,
} from "react"
import StoryTextOverlayNode from "./StoryTextOverlayNode"
import { storyImageDrawRect } from "@/lib/storyEditor/storyImageLayout"
import {
  STORY_CANVAS_ASPECT,
  storyTrashContainsCenter,
} from "@/lib/storyEditor/storyTextOverlay"
import type { useStoryEditorState } from "@/lib/storyEditor/useStoryEditorState"

type EditorApi = ReturnType<typeof useStoryEditorState>

type StoryEditorCanvasProps = {
  imageUrl: string
  imageNaturalSize: { width: number; height: number } | null
  editor: EditorApi
  className?: string
  onAddText: () => void
  addTextDisabled?: boolean
}

export default function StoryEditorCanvas({
  imageUrl,
  imageNaturalSize,
  editor,
  className = "",
  onAddText,
  addTextDisabled = false,
}: StoryEditorCanvasProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const [draggingOverlayId, setDraggingOverlayId] = useState<string | null>(
    null
  )
  const [trashHover, setTrashHover] = useState(false)

  const imageDragStart = useRef<{ width: number; height: number } | null>(null)
  const imagePointerOrigin = useRef<{ x: number; y: number } | null>(null)
  const imagePinchStart = useRef<{
    distance: number
    scale: number
  } | null>(null)
  const imagePointers = useRef<Map<number, { x: number; y: number }>>(new Map())
  const imageScaleWheelStart = useRef<number | null>(null)

  const {
    canvas,
    isEditingText,
    selectText,
    updateOverlayPosition,
    updateOverlayScale,
    updateOverlayRotation,
    deleteOverlay,
    beginEditingSelectedText,
    setCanvasSize,
    updateImageScale,
    updateImageOffset,
  } = editor

  useEffect(() => {
    const node = containerRef.current
    if (!node) return
    const observer = new ResizeObserver((entries) => {
      const entry = entries[0]
      if (!entry) return
      const { width, height } = entry.contentRect
      setCanvasSize({ width, height })
    })
    observer.observe(node)
    return () => observer.disconnect()
  }, [setCanvasSize])

  const canvasSize = editor.canvasSize
  const imageRect =
    imageNaturalSize && canvasSize.width > 0
      ? storyImageDrawRect(
          imageNaturalSize,
          canvasSize,
          canvas.imageScale,
          canvas.imageOffset,
          "cover"
        )
      : null

  const imageManipEnabled =
    !isEditingText && canvas.selectedTextID == null && imageRect != null

  const handleCanvasTap = useCallback(() => {
    if (!isEditingText) selectText(null)
  }, [isEditingText, selectText])

  const onImagePointerDown = (e: ReactPointerEvent) => {
    if (!imageManipEnabled) return
    e.stopPropagation()
    ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
    imagePointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY })

    if (imagePointers.current.size === 1) {
      imageDragStart.current = { ...canvas.imageOffset }
      imagePointerOrigin.current = { x: e.clientX, y: e.clientY }
    } else if (imagePointers.current.size === 2) {
      const pts = [...imagePointers.current.values()]
      imagePinchStart.current = {
        distance: Math.hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y),
        scale: canvas.imageScale,
      }
      imageDragStart.current = null
      imagePointerOrigin.current = null
    }
  }

  const onImagePointerMove = (e: ReactPointerEvent) => {
    if (!imageManipEnabled) return
    if (!imagePointers.current.has(e.pointerId)) return
    imagePointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY })

    if (imagePointers.current.size >= 2 && imagePinchStart.current) {
      const pts = [...imagePointers.current.values()]
      const distance = Math.hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y)
      const start = imagePinchStart.current
      if (start.distance > 0) {
        updateImageScale(start.scale * (distance / start.distance))
      }
      return
    }

    if (
      imagePointers.current.size === 1 &&
      imageDragStart.current &&
      imagePointerOrigin.current
    ) {
      const start = imageDragStart.current
      const origin = imagePointerOrigin.current
      updateImageOffset({
        width: start.width + (e.clientX - origin.x),
        height: start.height + (e.clientY - origin.y),
      })
    }
  }

  const onImagePointerUp = (e: ReactPointerEvent) => {
    imagePointers.current.delete(e.pointerId)
    if (imagePointers.current.size < 2) imagePinchStart.current = null
    if (imagePointers.current.size === 0) {
      imageDragStart.current = null
      imagePointerOrigin.current = null
    }
  }

  const onImageWheel = (e: ReactWheelEvent) => {
    if (!imageManipEnabled) return
    if (!e.ctrlKey && !e.metaKey) return
    e.preventDefault()
    if (imageScaleWheelStart.current == null) {
      imageScaleWheelStart.current = canvas.imageScale
    }
    const factor = Math.exp(-e.deltaY * 0.01)
    updateImageScale((imageScaleWheelStart.current ?? canvas.imageScale) * factor)
  }

  const onImageWheelEnd = () => {
    imageScaleWheelStart.current = null
  }

  return (
    <div className={className}>
      <div
        ref={containerRef}
        className="relative mx-auto w-full max-w-[min(100%,360px)] overflow-hidden rounded-2xl border border-white/10 bg-black shadow-lg shadow-black/40"
        style={{ aspectRatio: `${STORY_CANVAS_ASPECT}` }}
        onClick={handleCanvasTap}
        role="presentation"
      >
        <button
          type="button"
          disabled={addTextDisabled}
          onClick={(e) => {
            e.stopPropagation()
            onAddText()
          }}
          className="absolute right-2 top-2 z-20 flex min-h-11 min-w-11 items-center justify-center rounded-full border border-white/25 bg-black/55 px-3 text-base font-bold text-white shadow-lg backdrop-blur-sm transition hover:border-emerald-400/60 hover:bg-black/70 disabled:opacity-40"
          aria-label="Add text"
          data-testid="story-editor-add-text"
        >
          Aa
        </button>

        <div
          className={`absolute inset-0 z-0 touch-none ${
            imageManipEnabled ? "cursor-grab active:cursor-grabbing" : "pointer-events-none"
          }`}
          onPointerDown={onImagePointerDown}
          onPointerMove={onImagePointerMove}
          onPointerUp={onImagePointerUp}
          onPointerCancel={onImagePointerUp}
          onWheel={onImageWheel}
          onWheelCapture={onImageWheelEnd}
          aria-hidden={!imageManipEnabled}
        >
          {imageRect ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={imageUrl}
              alt=""
              draggable={false}
              className="pointer-events-none absolute max-w-none select-none"
              style={{
                width: imageRect.width,
                height: imageRect.height,
                left: imageRect.x,
                top: imageRect.y,
              }}
            />
          ) : (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={imageUrl}
              alt=""
              draggable={false}
              className="pointer-events-none absolute inset-0 h-full w-full select-none object-cover"
            />
          )}
        </div>

        {canvas.textOverlays.map((overlay) => {
          const isSelected = canvas.selectedTextID === overlay.id
          const overlayTransformsEnabled =
            !isEditingText || isSelected
          return (
          <StoryTextOverlayNode
            key={overlay.id}
            overlay={overlay}
            canvasSize={canvasSize}
            isSelected={isSelected}
            isEditingActive={isEditingText && isSelected}
            transformsEnabled={overlayTransformsEnabled}
            onSelect={() => selectText(overlay.id)}
            onMove={(center) => updateOverlayPosition(overlay.id, center)}
            onScale={(scale) => updateOverlayScale(overlay.id, scale)}
            onRotation={(radians) => updateOverlayRotation(overlay.id, radians)}
            onEdit={() => {
              selectText(overlay.id)
              beginEditingSelectedText()
            }}
            onDragBegan={() => {
              setDraggingOverlayId(overlay.id)
              setTrashHover(false)
            }}
            onDragLocation={(center) => {
              if (draggingOverlayId !== overlay.id) return
              setTrashHover(storyTrashContainsCenter(center, canvasSize))
            }}
            onDragEnded={(center) => {
              if (draggingOverlayId !== overlay.id) return
              if (storyTrashContainsCenter(center, canvasSize)) {
                deleteOverlay(overlay.id)
              }
              setDraggingOverlayId(null)
              setTrashHover(false)
            }}
          />
          )
        })}

        {draggingOverlayId ? (
          <div
            className="pointer-events-none absolute right-[10px] top-[10px] z-30 flex h-11 w-11 items-center justify-center rounded-full border transition-transform"
            style={{
              borderColor: trashHover ? "rgb(248 113 113)" : "rgba(255,255,255,0.2)",
              backgroundColor: trashHover
                ? "rgba(239, 68, 68, 0.9)"
                : "rgba(255,255,255,0.12)",
              transform: trashHover ? "scale(1.15)" : "scale(1)",
            }}
            aria-hidden
          >
            <span className="text-lg">{trashHover ? "🗑️" : "🗑"}</span>
          </div>
        ) : null}
      </div>
    </div>
  )
}
