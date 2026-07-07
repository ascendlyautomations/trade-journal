"use client"

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { createPortal } from "react-dom"
import {
  fillFrameSize,
  getImageCropPreset,
  type ImageCropPresetId,
} from "@/lib/imageCropPresets"
import {
  clampFillOffset,
  computeFillDrawRect,
  renderImageCrop,
  type ImageCropMode,
  type ImageCropOffset,
} from "@/lib/renderImageCrop"

type ImageCropModalProps = {
  open: boolean
  file: File | null
  preset: ImageCropPresetId
  onCancel: () => void
  onSave: (file: File) => void
}

type DragState = {
  pointerId: number
  startX: number
  startY: number
  startOffset: ImageCropOffset
}

export default function ImageCropModal({
  open,
  file,
  preset: presetId,
  onCancel,
  onSave,
}: ImageCropModalProps) {
  const preset = getImageCropPreset(presetId)
  const fillFrame = fillFrameSize(preset)

  const [mounted, setMounted] = useState(false)
  const [mode, setMode] = useState<ImageCropMode>(preset.defaultMode)
  const [offset, setOffset] = useState<ImageCropOffset>({ x: 0, y: 0 })
  const [imageSize, setImageSize] = useState<{ width: number; height: number } | null>(
    null
  )
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [frameWidth, setFrameWidth] = useState(0)
  const [saving, setSaving] = useState(false)
  const frameRef = useRef<HTMLDivElement>(null)
  const dragRef = useRef<DragState | null>(null)

  const showModeToggle = preset.modes.length > 1

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!open) return
    const prev = document.body.style.overflow
    document.body.style.overflow = "hidden"
    return () => {
      document.body.style.overflow = prev
    }
  }, [open])

  useEffect(() => {
    if (!open || !file) {
      setImageSize(null)
      setPreviewUrl(null)
      setMode(preset.defaultMode)
      setOffset({ x: 0, y: 0 })
      setSaving(false)
      return
    }

    const url = URL.createObjectURL(file)
    setPreviewUrl(url)
    setMode(preset.defaultMode)
    setOffset({ x: 0, y: 0 })

    const image = new Image()
    image.onload = () => {
      setImageSize({
        width: image.naturalWidth,
        height: image.naturalHeight,
      })
    }
    image.onerror = () => {
      setImageSize(null)
    }
    image.src = url

    return () => {
      URL.revokeObjectURL(url)
    }
  }, [open, file, preset.defaultMode])

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
  }, [open, mode])

  const displayScale = frameWidth > 0 ? frameWidth / fillFrame.width : 1

  const frameStyle = useMemo(() => {
    if (mode === "fit" && preset.fitNatural && imageSize) {
      return { aspectRatio: `${imageSize.width} / ${imageSize.height}` }
    }
    return { aspectRatio: String(preset.fillAspect) }
  }, [mode, preset.fitNatural, preset.fillAspect, imageSize])

  const drawRect = useMemo(() => {
    if (!imageSize || mode === "fit") return null
    return computeFillDrawRect(
      imageSize.width,
      imageSize.height,
      offset,
      fillFrame.width,
      fillFrame.height
    )
  }, [imageSize, mode, offset, fillFrame.width, fillFrame.height])

  const setFillOffset = useCallback(
    (next: ImageCropOffset) => {
      if (!imageSize) return
      const baseRect = computeFillDrawRect(
        imageSize.width,
        imageSize.height,
        { x: 0, y: 0 },
        fillFrame.width,
        fillFrame.height
      )
      setOffset(clampFillOffset(baseRect.width, baseRect.height, next, fillFrame.width, fillFrame.height))
    },
    [imageSize, fillFrame.width, fillFrame.height]
  )

  const handlePointerDown = useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (mode !== "fill" || saving) return
      event.currentTarget.setPointerCapture(event.pointerId)
      dragRef.current = {
        pointerId: event.pointerId,
        startX: event.clientX,
        startY: event.clientY,
        startOffset: offset,
      }
    },
    [mode, offset, saving]
  )

  const handlePointerMove = useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      const drag = dragRef.current
      if (!drag || drag.pointerId !== event.pointerId) return

      const deltaX = (event.clientX - drag.startX) / displayScale
      const deltaY = (event.clientY - drag.startY) / displayScale
      setFillOffset({
        x: drag.startOffset.x + deltaX,
        y: drag.startOffset.y + deltaY,
      })
    },
    [displayScale, setFillOffset]
  )

  const handlePointerUp = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    const drag = dragRef.current
    if (!drag || drag.pointerId !== event.pointerId) return
    dragRef.current = null
    event.currentTarget.releasePointerCapture(event.pointerId)
  }, [])

  const handleSave = useCallback(async () => {
    if (!file || saving) return
    setSaving(true)
    try {
      const cropped = await renderImageCrop(file, preset, mode, offset)
      onSave(cropped)
    } catch {
      setSaving(false)
    }
  }, [file, mode, offset, onSave, preset, saving])

  const frameMaskClass =
    preset.mask === "circle"
      ? "rounded-full"
      : preset.mask === "rounded"
        ? "rounded-2xl"
        : "rounded-xl"

  if (!open || !mounted || !file) return null

  return createPortal(
    <div
      className="fixed inset-0 z-[10070] flex items-start justify-center overflow-y-auto p-4 sm:items-center"
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
        aria-label={preset.title}
        className="relative my-auto flex w-full max-w-xl max-h-[min(92dvh,calc(100dvh-2rem))] flex-col overflow-hidden rounded-2xl border border-white/10 bg-gradient-to-br from-[#0f172a] via-[#132a4a] to-[#0f172a] shadow-2xl shadow-black/40"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="shrink-0 px-6 pb-4 pt-6">
          <h2 className="text-lg font-semibold text-white">{preset.title}</h2>
          <p className="mt-1 text-sm text-gray-400">{preset.subtitle}</p>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-6">
          <div
            ref={frameRef}
            className={`relative w-full overflow-hidden border border-white/10 ${
              mode === "fill" && preset.mask === "none" ? "bg-[#111827]" : ""
            } ${frameMaskClass}`}
            style={frameStyle}
            onPointerDown={handlePointerDown}
            onPointerMove={handlePointerMove}
            onPointerUp={handlePointerUp}
            onPointerCancel={handlePointerUp}
          >
            {previewUrl ? (
              mode === "fit" ? (
                <img
                  src={previewUrl}
                  alt=""
                  draggable={false}
                  className={`block h-full w-full select-none transition-opacity duration-200 ${
                    saving ? "opacity-70" : "opacity-100"
                  }`}
                />
              ) : drawRect ? (
                <img
                  src={previewUrl}
                  alt=""
                  draggable={false}
                  className={`absolute max-w-none select-none transition-opacity duration-200 cursor-grab active:cursor-grabbing ${
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
              )
            ) : (
              <div className="absolute inset-0 animate-pulse bg-white/5" aria-hidden />
            )}
          </div>

          {showModeToggle ? (
            <>
              <div className="mt-4 flex rounded-xl border border-white/10 bg-white/5 p-1">
                {preset.modes.map((option) => {
                  const active = mode === option
                  return (
                    <button
                      key={option}
                      type="button"
                      disabled={saving}
                      onClick={() => {
                        setMode(option)
                        setOffset({ x: 0, y: 0 })
                      }}
                      className={`flex-1 rounded-lg px-3 py-2 text-sm font-medium transition ${
                        active
                          ? "bg-white/10 text-white shadow-sm"
                          : "text-gray-400 hover:text-gray-200"
                      }`}
                    >
                      {option === "fit" ? "Fit" : "Fill"}
                    </button>
                  )
                })}
              </div>
              <p className="mt-2 text-xs text-gray-500">
                {mode === "fit" ? preset.fitHelp : preset.fillHelp}
              </p>
            </>
          ) : (
            <p className="mt-3 text-xs text-gray-500">{preset.fillHelp}</p>
          )}
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
            <button
              type="button"
              disabled={saving || !imageSize}
              onClick={() => void handleSave()}
              className="h-11 rounded-lg bg-gradient-to-r from-blue-500 to-emerald-500 px-5 text-sm font-semibold text-white transition hover:opacity-90 disabled:opacity-50"
            >
              {saving ? "Saving…" : "Save"}
            </button>
          </div>
        </div>
      </div>
    </div>,
    document.body
  )
}
