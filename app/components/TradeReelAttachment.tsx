"use client"

import { useEffect, useRef, useState } from "react"
import ReelVideoPosterFrame from "@/app/components/ReelVideoPosterFrame"
import ReelVideoFilePreview from "@/app/components/ReelVideoFilePreview"
import type { ReelRow } from "@/lib/reels"
import {
  TRADE_OPTIONAL_ATTACHMENT_LABEL_CLASS,
  TRADE_FULL_INPUT_MEDIA_UPLOAD_CLASS,
} from "@/lib/tradeFormUi"
import {
  readReelVideoMetadata,
  REEL_MAX_DURATION_LABEL,
  validateReelVideoFile,
} from "@/lib/reelVideo"

export type TradeReelAttachmentProps = {
  variant?: "quick" | "full"
  disabled?: boolean
  pendingFile: File | null
  onPendingFileChange: (file: File | null) => void
  attachedReel?: ReelRow | null
  onDeleteAttached?: () => void | Promise<void>
  deleteBusy?: boolean
  label?: string
  labelClassName?: string
}

function formatDuration(totalSeconds: number): string {
  const seconds = Math.max(0, Math.floor(totalSeconds))
  const mins = Math.floor(seconds / 60)
  const secs = seconds % 60
  return `${mins}:${String(secs).padStart(2, "0")}`
}

export default function TradeReelAttachment({
  variant = "full",
  disabled = false,
  pendingFile,
  onPendingFileChange,
  attachedReel = null,
  onDeleteAttached,
  deleteBusy = false,
  label,
  labelClassName,
}: TradeReelAttachmentProps) {
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [durationSeconds, setDurationSeconds] = useState<number | null>(null)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [validating, setValidating] = useState(false)

  useEffect(() => {
    if (!pendingFile) {
      setDurationSeconds(null)
      return
    }

    let cancelled = false

    void readReelVideoMetadata(pendingFile)
      .then((meta) => {
        if (!cancelled) setDurationSeconds(meta.durationSeconds)
      })
      .catch(() => {
        if (!cancelled) setDurationSeconds(null)
      })

    return () => {
      cancelled = true
    }
  }, [pendingFile])

  const handleFileSelect = async (file: File | null) => {
    if (!file || disabled) return
    setErrorMessage(null)

    const validationError = validateReelVideoFile(file)
    if (validationError) {
      setErrorMessage(validationError.message)
      return
    }

    setValidating(true)
    try {
      await readReelVideoMetadata(file)
      onPendingFileChange(file)
    } catch (err) {
      setErrorMessage(
        err instanceof Error ? err.message : "Could not read this video."
      )
      onPendingFileChange(null)
    } finally {
      setValidating(false)
    }
  }

  const showAttached = attachedReel != null && pendingFile == null

  const uploadButtonClass =
    variant === "quick"
      ? "mt-2 h-12 w-full rounded-lg border border-dashed border-white/20 bg-white/5 text-sm font-medium text-gray-200 transition hover:bg-white/10 disabled:opacity-50"
      : TRADE_FULL_INPUT_MEDIA_UPLOAD_CLASS

  const resolvedLabelClass =
    labelClassName ??
    (variant === "quick"
      ? TRADE_OPTIONAL_ATTACHMENT_LABEL_CLASS
      : "block text-xs text-gray-400 mb-1")

  const resolvedLabel =
    label ?? (variant === "quick" ? "🎥 Add Clip (Optional)" : "Add Clip (Optional)")

  return (
    <div className="border-t border-white/10 pt-4 mt-4">
      <label className={resolvedLabelClass}>{resolvedLabel}</label>

      <input
        ref={fileInputRef}
        type="file"
        accept="video/mp4,video/quicktime,.mp4,.mov"
        className="hidden"
        disabled={disabled || validating || deleteBusy}
        onChange={(e) => {
          const file = e.target.files?.[0] ?? null
          e.target.value = ""
          void handleFileSelect(file)
        }}
      />

      {showAttached ? (
        <div className="mt-2 space-y-3">
          <div className="flex items-center gap-3">
            <div className="relative h-20 w-14 shrink-0 overflow-hidden rounded-lg border border-white/10 bg-black/40">
              <ReelVideoPosterFrame
                thumbnailUrl={attachedReel.thumbnail_url}
                videoUrl={attachedReel.video_url}
                className="h-full w-full object-cover"
              />
              {attachedReel.duration_seconds != null ? (
                <span className="absolute bottom-1 right-1 rounded bg-black/70 px-1 text-[9px] text-white tabular-nums">
                  {formatDuration(attachedReel.duration_seconds)}
                </span>
              ) : null}
            </div>
            <p className="text-sm text-gray-300">Clip attached</p>
          </div>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              disabled={disabled || deleteBusy}
              onClick={() => fileInputRef.current?.click()}
              className="rounded-lg border border-white/15 bg-white/5 px-3 py-1.5 text-xs font-medium text-white transition hover:bg-white/10 disabled:opacity-50"
            >
              Replace
            </button>
            {onDeleteAttached ? (
              <button
                type="button"
                disabled={disabled || deleteBusy}
                onClick={() => void onDeleteAttached()}
                className="rounded-lg border border-red-500/30 bg-red-500/10 px-3 py-1.5 text-xs font-medium text-red-300 transition hover:bg-red-500/20 disabled:opacity-50"
              >
                {deleteBusy ? "Deleting…" : "Delete"}
              </button>
            ) : null}
          </div>
        </div>
      ) : pendingFile ? (
        <div className="mt-2 space-y-3">
          <ReelVideoFilePreview
            file={pendingFile}
            containerClassName={
              variant === "quick"
                ? "mx-auto max-w-[200px] overflow-hidden rounded-lg border border-white/10 bg-black/40"
                : "mx-auto max-w-[220px] overflow-hidden rounded-lg border border-white/10 bg-black/40"
            }
          />
          {durationSeconds != null ? (
            <p className="text-center text-xs text-gray-400 tabular-nums">
              Duration: {formatDuration(durationSeconds)}
            </p>
          ) : null}
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              disabled={disabled || validating}
              onClick={() => fileInputRef.current?.click()}
              className="rounded-lg border border-white/15 bg-white/5 px-3 py-1.5 text-xs font-medium text-white transition hover:bg-white/10 disabled:opacity-50"
            >
              Change video
            </button>
            <button
              type="button"
              disabled={disabled}
              onClick={() => {
                onPendingFileChange(null)
                setErrorMessage(null)
              }}
              className="rounded-lg border border-red-500/30 bg-red-500/10 px-3 py-1.5 text-xs font-medium text-red-300 transition hover:bg-red-500/20 disabled:opacity-50"
            >
              Delete
            </button>
          </div>
        </div>
      ) : (
        <button
          type="button"
          disabled={disabled || validating}
          onClick={() => fileInputRef.current?.click()}
          className={uploadButtonClass}
        >
          {validating ? "Checking video…" : "Upload Clip"}
        </button>
      )}

      {variant === "quick" && !showAttached && !pendingFile ? (
        <p className="mt-1.5 text-xs text-gray-500">
          MP4 or MOV · up to {REEL_MAX_DURATION_LABEL}
        </p>
      ) : null}

      {errorMessage ? (
        <p className="mt-2 rounded-lg border border-red-500/30 bg-red-500/10 px-3 py-2 text-xs text-red-200">
          {errorMessage}
        </p>
      ) : null}
    </div>
  )
}
