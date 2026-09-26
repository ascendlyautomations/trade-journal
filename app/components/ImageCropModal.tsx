"use client"

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { createPortal } from "react-dom"
import {
  contentAspectLabel,
  contentCoverLayout,
  contentLogicalFrame,
  contentPresentationAspect,
  CONTENT_IMAGE_ASPECTS,
  CONTENT_IMAGE_V2_DEFAULT_ASPECT,
  CONTENT_IMAGE_V2_MAX_ZOOM,
  CONTENT_IMAGE_V2_PRESET,
  type ContentImageAspect,
} from "@/lib/contentImageV2"
import {
  fillFrameSize,
  getImageCropPreset,
  IMAGE_CROP_EDITOR_HELP,
  type ImageCropPresetId,
} from "@/lib/imageCropPresets"
import { renderContentImageV2 } from "@/lib/renderContentImageV2"
import { prepareImageForUpload } from "@/lib/imagePreparation"
import { STORY_ASPECT } from "@/lib/semanticImage"
import {
  clampZoom,
  clampZoomPanOffset,
  computeZoomPanDrawRect,
  DEFAULT_ZOOM_PAN_TRANSFORM,
  renderZoomPanCrop,
  type ZoomPanTransform,
} from "@/lib/renderImageCrop"
import { useModalScrollLock, MODAL_OVERLAY_SAFE_PADDING_CLASS } from "@/app/components/ui/modalLayout"
import ActionButton from "@/app/components/ui/ActionButton"

export type ImageCropModalPreset = ImageCropPresetId | "contentV2"

type ImageCropModalProps = {
  open: boolean
  file: File | null
  preset: ImageCropModalPreset
  onCancel: () => void
  onSave: (file: File) => void
}

type DragState = {
  pointerId: number
  startX: number
  startY: number
  startOffset: ZoomPanTransform["offset"]
}

type PinchState = {
  pointerIds: [number, number]
  startDistance: number
  startZoom: number
  startOffset: ZoomPanTransform["offset"]
}

export default function ImageCropModal({
  open,
  file,
  preset: presetId,
  onCancel,
  onSave,
}: ImageCropModalProps) {
  const isContentV2 = presetId === CONTENT_IMAGE_V2_PRESET
  const fixedCover =
    presetId === "avatar" || presetId === "room"
      ? "avatar"
      : presetId === "story"
        ? "story"
        : null
  const usesCoverLayout = isContentV2 || fixedCover != null
  const preset = isContentV2 ? null : getImageCropPreset(presetId)
  const [contentAspect, setContentAspect] = useState<ContentImageAspect>(
    CONTENT_IMAGE_V2_DEFAULT_ASPECT
  )

  const [mounted, setMounted] = useState(false)
  const [transform, setTransform] = useState<ZoomPanTransform>(
    DEFAULT_ZOOM_PAN_TRANSFORM
  )
  const [imageSize, setImageSize] = useState<{ width: number; height: number } | null>(
    null
  )
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [frameWidth, setFrameWidth] = useState(0)
  const [saving, setSaving] = useState(false)
  const [decodeError, setDecodeError] = useState<string | null>(null)
  const frameRef = useRef<HTMLDivElement>(null)
  const dragRef = useRef<DragState | null>(null)
  const pinchRef = useRef<PinchState | null>(null)
  const activePointersRef = useRef(new Map<number, { x: number; y: number }>())

  useModalScrollLock(open)

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!open || !file) {
      setImageSize(null)
      setPreviewUrl(null)
      setTransform(DEFAULT_ZOOM_PAN_TRANSFORM)
      setContentAspect(CONTENT_IMAGE_V2_DEFAULT_ASPECT)
      setDecodeError(null)
      setSaving(false)
      activePointersRef.current.clear()
      dragRef.current = null
      pinchRef.current = null
      return
    }

    const url = URL.createObjectURL(file)
    setPreviewUrl(url)
    setTransform(DEFAULT_ZOOM_PAN_TRANSFORM)
    setContentAspect(CONTENT_IMAGE_V2_DEFAULT_ASPECT)
    setDecodeError(null)

    const image = new Image()
    image.onload = () => {
      setImageSize({
        width: image.naturalWidth,
        height: image.naturalHeight,
      })
    }
    image.onerror = () => {
      setImageSize(null)
      setDecodeError(
        file.type.toLowerCase().includes("heic") ||
          file.type.toLowerCase().includes("heif") ||
          file.name.toLowerCase().endsWith(".heic") ||
          file.name.toLowerCase().endsWith(".heif")
          ? "This browser can't read that HEIC photo. Export it as JPEG and try again."
          : "Couldn't read that image. Try a JPEG or PNG."
      )
    }
    image.src = url

    return () => {
      URL.revokeObjectURL(url)
    }
  }, [open, file])

  useEffect(() => {
    if (!open) return
    const node = frameRef.current
    if (!node) return

    const updateWidth = () => {
      setFrameWidth(node.clientWidth)
    }

    updateWidth()
    const observer = new ResizeObserver(updateWidth)
    observer.observe(node)
    return () => observer.disconnect()
  }, [open])

  const presentationAspect =
    isContentV2 && imageSize
      ? contentPresentationAspect(contentAspect)
      : fixedCover === "story"
        ? STORY_ASPECT
        : fixedCover === "avatar"
          ? 1
          : preset?.fillAspect ?? 1

  const fillFrame = usesCoverLayout
    ? contentLogicalFrame(presentationAspect)
    : fillFrameSize(preset!)

  const displayScale = frameWidth > 0 ? frameWidth / fillFrame.width : 1
  const zoomMax = usesCoverLayout ? CONTENT_IMAGE_V2_MAX_ZOOM : preset!.maxZoom

  const clampedTransform = useMemo(() => {
    if (!imageSize) return transform
    if (usesCoverLayout) {
      const frame = contentLogicalFrame(presentationAspect)
      const layout = contentCoverLayout(
        imageSize.width,
        imageSize.height,
        frame,
        transform
      )
      return { zoom: layout.zoom, offset: layout.offset }
    }
    const zoom = clampZoom(transform.zoom, preset!.maxZoom)
    const offset = clampZoomPanOffset(
      imageSize.width,
      imageSize.height,
      fillFrame.width,
      fillFrame.height,
      zoom,
      transform.offset
    )
    return { zoom, offset }
  }, [
    imageSize,
    transform,
    fillFrame.width,
    fillFrame.height,
    preset,
    usesCoverLayout,
    presentationAspect,
    contentAspect,
  ])

  const drawRect = useMemo(() => {
    if (!imageSize) return null
    if (usesCoverLayout) {
      const frame = contentLogicalFrame(presentationAspect)
      const layout = contentCoverLayout(
        imageSize.width,
        imageSize.height,
        frame,
        clampedTransform
      )
      return {
        x: layout.originX,
        y: layout.originY,
        width: layout.displayWidth,
        height: layout.displayHeight,
      }
    }
    return computeZoomPanDrawRect(
      imageSize.width,
      imageSize.height,
      fillFrame.width,
      fillFrame.height,
      clampedTransform.zoom,
      clampedTransform.offset
    )
  }, [
    imageSize,
    fillFrame.width,
    fillFrame.height,
    clampedTransform,
    usesCoverLayout,
    presentationAspect,
  ])

  const applyTransform = useCallback(
    (next: ZoomPanTransform) => {
      if (!imageSize) {
        setTransform(next)
        return
      }
      if (usesCoverLayout) {
        const frame = contentLogicalFrame(presentationAspect)
        const layout = contentCoverLayout(
          imageSize.width,
          imageSize.height,
          frame,
          next
        )
        setTransform({ zoom: layout.zoom, offset: layout.offset })
        return
      }
      const zoom = clampZoom(next.zoom, preset!.maxZoom)
      const offset = clampZoomPanOffset(
        imageSize.width,
        imageSize.height,
        fillFrame.width,
        fillFrame.height,
        zoom,
        next.offset
      )
      setTransform({ zoom, offset })
    },
    [
      imageSize,
      fillFrame.width,
      fillFrame.height,
      preset,
      usesCoverLayout,
      presentationAspect,
    ]
  )

  const pointerDistance = useCallback(
    (a: { x: number; y: number }, b: { x: number; y: number }) =>
      Math.hypot(a.x - b.x, a.y - b.y),
    []
  )

  const handlePointerDown = useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (saving) return
      event.currentTarget.setPointerCapture(event.pointerId)
      activePointersRef.current.set(event.pointerId, {
        x: event.clientX,
        y: event.clientY,
      })

      const pointers = [...activePointersRef.current.entries()]
      if (pointers.length >= 2) {
        const [first, second] = pointers.slice(0, 2)
        pinchRef.current = {
          pointerIds: [first[0], second[0]],
          startDistance: pointerDistance(first[1], second[1]),
          startZoom: clampedTransform.zoom,
          startOffset: clampedTransform.offset,
        }
        dragRef.current = null
        return
      }

      dragRef.current = {
        pointerId: event.pointerId,
        startX: event.clientX,
        startY: event.clientY,
        startOffset: clampedTransform.offset,
      }
    },
    [clampedTransform.offset, clampedTransform.zoom, pointerDistance, saving]
  )

  const handlePointerMove = useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (!activePointersRef.current.has(event.pointerId)) return
      activePointersRef.current.set(event.pointerId, {
        x: event.clientX,
        y: event.clientY,
      })

      const pinch = pinchRef.current
      if (pinch && pinch.pointerIds.includes(event.pointerId)) {
        const first = activePointersRef.current.get(pinch.pointerIds[0])
        const second = activePointersRef.current.get(pinch.pointerIds[1])
        if (!first || !second || pinch.startDistance <= 0) return

        const distance = pointerDistance(first, second)
        const ratio = distance / pinch.startDistance
        applyTransform({
          zoom: pinch.startZoom * ratio,
          offset: pinch.startOffset,
        })
        return
      }

      const drag = dragRef.current
      if (!drag || drag.pointerId !== event.pointerId) return

      const deltaX = (event.clientX - drag.startX) / displayScale
      const deltaY = (event.clientY - drag.startY) / displayScale
      applyTransform({
        zoom: clampedTransform.zoom,
        offset: {
          x: drag.startOffset.x + deltaX,
          y: drag.startOffset.y + deltaY,
        },
      })
    },
    [applyTransform, clampedTransform.zoom, displayScale, pointerDistance]
  )

  const handlePointerUp = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    activePointersRef.current.delete(event.pointerId)
    if (pinchRef.current?.pointerIds.includes(event.pointerId)) {
      pinchRef.current = null
    }
    const drag = dragRef.current
    if (drag?.pointerId === event.pointerId) {
      dragRef.current = null
    }
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId)
    }
  }, [])

  const handleWheel = useCallback(
    (event: React.WheelEvent<HTMLDivElement>) => {
      if (saving) return
      event.preventDefault()
      const delta = event.deltaY > 0 ? -0.08 : 0.08
      applyTransform({
        zoom: clampedTransform.zoom + delta,
        offset: clampedTransform.offset,
      })
    },
    [applyTransform, clampedTransform, saving]
  )

  const handleResetFit = useCallback(() => {
    applyTransform(DEFAULT_ZOOM_PAN_TRANSFORM)
  }, [applyTransform])

  const handleSave = useCallback(async () => {
    if (!file || saving) return
    setSaving(true)
    setDecodeError(null)
    try {
      const cropped = isContentV2
        ? await renderContentImageV2(file, {
            aspect: contentAspect,
            transform: clampedTransform,
          })
        : fixedCover
          ? await prepareImageForUpload(
              presetId === "story"
                ? "story"
                : presetId === "room"
                  ? "room"
                  : "avatar",
              file,
              { transform: clampedTransform }
            )
          : await renderZoomPanCrop(file, preset!, clampedTransform)
      onSave(cropped)
    } catch (error) {
      setDecodeError(
        error instanceof Error ? error.message : "Couldn't prepare that image."
      )
      setSaving(false)
    }
  }, [file, onSave, preset, presetId, clampedTransform, saving, isContentV2, fixedCover, contentAspect])

  const frameMaskClass = !preset
    ? "rounded-xl"
    : preset.mask === "circle"
      ? "rounded-full"
      : preset.mask === "rounded"
        ? "rounded-2xl"
        : "rounded-xl"

  const editorTitle = isContentV2 ? "Adjust image" : preset!.title
  const editorSubtitle = isContentV2
    ? "Drag and zoom to frame the photo. The frame stays covered."
    : preset!.subtitle

  if (!open || !mounted || !file) return null

  return createPortal(
    <div
      className={`fixed inset-0 z-[10070] flex items-start justify-center overscroll-contain ${MODAL_OVERLAY_SAFE_PADDING_CLASS} sm:items-center`}
      role="presentation"
      onClick={(e) => e.stopPropagation()}
      onMouseDown={(e) => e.stopPropagation()}
    >
      <div
        className="absolute inset-0 bg-black/60 backdrop-blur-md"
        aria-hidden
        onClick={saving ? undefined : onCancel}
      />
      <div
        role="dialog"
        aria-modal="true"
        aria-label={editorTitle}
        className="relative my-auto flex w-full max-w-xl max-h-[min(92dvh,calc(100dvh-2rem-var(--safe-area-top)-var(--safe-area-bottom)))] flex-col overflow-hidden rounded-2xl border border-white/10 bg-gradient-to-br from-[#0f172a] via-[#132a4a] to-[#0f172a] shadow-2xl shadow-black/40"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="shrink-0 px-6 pb-4 pt-6">
          <h2 className="text-lg font-semibold text-white">{editorTitle}</h2>
          <p className="mt-1 text-sm text-gray-400">{editorSubtitle}</p>
          {decodeError ? (
            <p className="mt-2 text-sm text-red-300" role="alert">
              {decodeError}
            </p>
          ) : null}
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-6">
          {isContentV2 && imageSize ? (
            <div
              className="mb-3 flex flex-wrap gap-2"
              role="radiogroup"
              aria-label="Crop ratio"
            >
              {CONTENT_IMAGE_ASPECTS.map((option) => {
                const selected = option === contentAspect
                return (
                  <button
                    key={option}
                    type="button"
                    role="radio"
                    aria-checked={selected}
                    disabled={saving}
                    onClick={() => setContentAspect(option)}
                    className={`rounded-full border px-3 py-1 text-xs font-medium transition ${
                      selected
                        ? "border-blue-400 bg-blue-500/20 text-white"
                        : "border-white/15 bg-white/5 text-gray-300 hover:bg-white/10"
                    }`}
                  >
                    {contentAspectLabel(option)}
                  </button>
                )
              })}
            </div>
          ) : null}
          <div
            ref={frameRef}
            className={`relative w-full touch-none overflow-hidden border border-white/10 bg-[#0f172a] ${frameMaskClass}`}
            style={{ aspectRatio: String(presentationAspect) }}
            onPointerDown={handlePointerDown}
            onPointerMove={handlePointerMove}
            onPointerUp={handlePointerUp}
            onPointerCancel={handlePointerUp}
            onWheel={handleWheel}
          >
            {previewUrl && drawRect ? (
              <img
                src={previewUrl}
                alt=""
                draggable={false}
                className={`absolute max-w-none select-none cursor-grab active:cursor-grabbing ${
                  saving ? "opacity-70" : "opacity-100"
                }`}
                style={{
                  width: drawRect.width * displayScale,
                  height: drawRect.height * displayScale,
                  left: drawRect.x * displayScale,
                  top: drawRect.y * displayScale,
                }}
              />
            ) : (
              <div className="absolute inset-0 animate-pulse bg-white/5" aria-hidden />
            )}
          </div>

          <div className="mt-4 space-y-3">
            <div className="flex items-center gap-3">
              <button
                type="button"
                disabled={saving || clampedTransform.zoom <= 1}
                onClick={() =>
                  applyTransform({
                    zoom: clampedTransform.zoom - 0.1,
                    offset: clampedTransform.offset,
                  })
                }
                className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg border border-white/15 bg-white/5 text-lg text-white transition hover:bg-white/10 disabled:opacity-40"
                aria-label="Zoom out"
              >
                −
              </button>
              <input
                type="range"
                min={1}
                max={zoomMax}
                step={0.01}
                value={clampedTransform.zoom}
                disabled={saving}
                onChange={(e) =>
                  applyTransform({
                    zoom: Number(e.target.value),
                    offset: clampedTransform.offset,
                  })
                }
                className="min-w-0 flex-1 accent-blue-500"
                aria-label="Zoom"
              />
              <button
                type="button"
                disabled={saving || clampedTransform.zoom >= zoomMax}
                onClick={() =>
                  applyTransform({
                    zoom: clampedTransform.zoom + 0.1,
                    offset: clampedTransform.offset,
                  })
                }
                className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg border border-white/15 bg-white/5 text-lg text-white transition hover:bg-white/10 disabled:opacity-40"
                aria-label="Zoom in"
              >
                +
              </button>
            </div>

            <div className="flex flex-wrap items-center justify-between gap-2">
              <p className="text-xs text-gray-400">
                {usesCoverLayout
                  ? "Drag to reposition. Pinch or use the slider to zoom (1×–4×). Reset returns to the covered frame."
                  : IMAGE_CROP_EDITOR_HELP}
              </p>
              <button
                type="button"
                disabled={
                  saving ||
                  (clampedTransform.zoom === 1 &&
                    clampedTransform.offset.x === 0 &&
                    clampedTransform.offset.y === 0)
                }
                onClick={handleResetFit}
                className="rounded-lg border border-white/15 bg-white/5 px-3 py-1.5 text-xs font-medium text-gray-200 transition hover:bg-white/10 disabled:opacity-40"
              >
                {usesCoverLayout ? "Reset" : "Reset to Fit"}
              </button>
            </div>
          </div>
        </div>

        <div className="shrink-0 border-t border-white/10 px-6 py-4">
          <div className="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
            <button
              type="button"
              disabled={saving}
              onClick={onCancel}
              className="h-11 rounded-lg border border-white/20 bg-white/5 px-4 text-sm font-medium text-slate-200 transition hover:bg-white/10 disabled:opacity-50"
            >
              Cancel
            </button>
            <ActionButton
              type="button"
              disabled={!imageSize}
              syncing={saving}
              syncingLabel="Saving…"
              onClick={() => void handleSave()}
              className="h-11 rounded-lg bg-blue-500 px-5 text-sm font-semibold text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:bg-blue-500"
            >
              Save
            </ActionButton>
          </div>
        </div>
      </div>
    </div>,
    document.body
  )
}
