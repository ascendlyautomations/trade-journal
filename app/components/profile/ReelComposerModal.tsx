"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import Modal from "@/app/components/ui/Modal"
import { supabase } from "@/lib/supabaseClient"
import { publishReel, updateReelCaption, type ReelRow, isTradeAttachedReel } from "@/lib/reels"
import {
  readReelVideoMetadata,
  REEL_MAX_DURATION_LABEL,
  REEL_MAX_DURATION_SECONDS,
  validateReelVideoFile,
} from "@/lib/reelVideo"

type ReelComposerModalProps = {
  open: boolean
  userId: string | null
  onClose: () => void
  onPublished?: (reelId: string) => void
  /** When set, edits caption only — video is read-only. */
  editReel?: ReelRow | null
  onSaved?: (reel: ReelRow) => void
}

export default function ReelComposerModal({
  open,
  userId,
  onClose,
  onPublished,
  editReel = null,
  onSaved,
}: ReelComposerModalProps) {
  const isEditMode = editReel != null
  const isTradeReplayEdit = isEditMode && isTradeAttachedReel(editReel)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const previewUrlRef = useRef<string | null>(null)

  const [videoFile, setVideoFile] = useState<File | null>(null)
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [caption, setCaption] = useState("")
  const [publishing, setPublishing] = useState(false)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [validating, setValidating] = useState(false)

  const revokePreview = useCallback(() => {
    if (previewUrlRef.current?.startsWith("blob:")) {
      URL.revokeObjectURL(previewUrlRef.current)
    }
    previewUrlRef.current = null
  }, [])

  const resetForm = useCallback(() => {
    revokePreview()
    setVideoFile(null)
    setPreviewUrl(null)
    setCaption("")
    setErrorMessage(null)
    setValidating(false)
    setPublishing(false)
  }, [revokePreview])

  const handleClose = useCallback(() => {
    if (publishing) return
    resetForm()
    onClose()
  }, [onClose, publishing, resetForm])

  useEffect(() => {
    if (!open) {
      resetForm()
      return
    }
    if (isEditMode && editReel && !isTradeAttachedReel(editReel)) {
      setCaption(editReel.caption ?? "")
      setErrorMessage(null)
    }
  }, [open, isEditMode, editReel, resetForm])

  const handleFileSelect = async (file: File | null) => {
    if (!file || isEditMode) return
    setErrorMessage(null)

    const validationError = validateReelVideoFile(file)
    if (validationError) {
      setErrorMessage(validationError.message)
      return
    }

    setValidating(true)
    try {
      await readReelVideoMetadata(file)
    } catch (err) {
      setErrorMessage(
        err instanceof Error ? err.message : "Could not read this video."
      )
      setValidating(false)
      return
    }

    revokePreview()
    const nextPreview = URL.createObjectURL(file)
    previewUrlRef.current = nextPreview
    setVideoFile(file)
    setPreviewUrl(nextPreview)
    setValidating(false)
  }

  const handlePublish = async () => {
    if (!userId || !videoFile || publishing || isEditMode) return

    setPublishing(true)
    setErrorMessage(null)

    const result = await publishReel(supabase, {
      userId,
      file: videoFile,
      caption,
    })

    setPublishing(false)

    if ("error" in result) {
      setErrorMessage(result.error)
      return
    }

    onPublished?.(result.reel.id)
    resetForm()
    onClose()
  }

  const handleSaveEdit = async () => {
    if (!userId || !editReel || publishing) return

    const trimmed = caption.trim()
    const previousCaption = editReel.caption ?? null
    const optimistic: ReelRow = {
      ...editReel,
      caption: trimmed || null,
    }

    setPublishing(true)
    setErrorMessage(null)
    onSaved?.(optimistic)

    const result = await updateReelCaption(supabase, {
      reelId: editReel.id,
      userId,
      caption: trimmed,
    })

    setPublishing(false)

    if ("error" in result) {
      onSaved?.({ ...editReel, caption: previousCaption })
      setErrorMessage(result.error)
      return
    }

    onSaved?.(result.reel)
    resetForm()
    onClose()
  }

  const readOnlyVideoUrl = isEditMode ? String(editReel?.video_url ?? "") : null
  const readOnlyPoster = isEditMode
    ? String(editReel?.thumbnail_url ?? "")
    : undefined

  return (
    <Modal
      open={open}
      onClose={handleClose}
      title={isTradeReplayEdit ? "Trade Replay" : isEditMode ? "Edit Reel" : "Create Reel"}
      size="md"
      panelClassName="max-w-lg p-4 sm:p-6"
      footer={
        <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <button
            type="button"
            disabled={publishing}
            onClick={handleClose}
            className="rounded-lg border border-white/10 bg-white/5 px-4 py-2 text-sm text-gray-200 transition hover:bg-white/10 disabled:opacity-50"
          >
            Cancel
          </button>
          {isEditMode && !isTradeReplayEdit ? (
            <button
              type="button"
              disabled={publishing}
              onClick={() => void handleSaveEdit()}
              className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-emerald-500 disabled:opacity-50"
            >
              {publishing ? "Saving…" : "Save"}
            </button>
          ) : isEditMode ? (
            <button
              type="button"
              disabled={publishing}
              onClick={handleClose}
              className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-emerald-500 disabled:opacity-50"
            >
              Done
            </button>
          ) : (
            <button
              type="button"
              disabled={!videoFile || publishing || validating}
              onClick={() => void handlePublish()}
              className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-emerald-500 disabled:opacity-50"
            >
              {publishing ? "Publishing…" : "Publish"}
            </button>
          )}
        </div>
      }
    >
      {isEditMode ? (
        <div className="space-y-4">
          <div className="mx-auto w-full max-w-[220px] overflow-hidden rounded-xl border border-white/10 bg-black shadow-lg shadow-black/40">
            <video
              src={readOnlyVideoUrl ?? undefined}
              poster={readOnlyPoster}
              className="aspect-[9/16] w-full object-cover"
              controls
              playsInline
              preload="metadata"
            />
          </div>
          {isTradeReplayEdit ? (
            <p className="text-center text-sm text-gray-400">
              Caption comes from your trade description. Use Replace Video from
              the reel menu to change the video.
            </p>
          ) : (
            <>
              <p className="text-center text-xs text-gray-500">
                Video cannot be changed after publishing.
              </p>
              <div>
                <label
                  htmlFor="reel-caption-edit"
                  className="mb-1.5 block text-xs font-medium uppercase tracking-wide text-gray-400"
                >
                  Caption
                </label>
                <textarea
                  id="reel-caption-edit"
                  value={caption}
                  onChange={(e) => setCaption(e.target.value)}
                  rows={3}
                  maxLength={2200}
                  placeholder="Write a caption…"
                  disabled={publishing}
                  className="w-full resize-none rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm text-white placeholder:text-gray-500 focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/30 disabled:opacity-60"
                />
              </div>
            </>
          )}
        </div>
      ) : (
        <>
          <p className="mb-4 text-sm text-gray-400">
            Upload a vertical video up to {REEL_MAX_DURATION_SECONDS} seconds
            (MP4 or MOV, max 100 MB).
          </p>

          <input
            ref={fileInputRef}
            type="file"
            accept="video/mp4,video/quicktime,.mp4,.mov"
            className="hidden"
            onChange={(e) => {
              const file = e.target.files?.[0] ?? null
              e.target.value = ""
              void handleFileSelect(file)
            }}
          />

          {!videoFile ? (
            <button
              type="button"
              disabled={validating}
              onClick={() => fileInputRef.current?.click()}
              className="flex w-full flex-col items-center justify-center gap-2 rounded-xl border border-dashed border-white/20 bg-white/5 px-4 py-10 text-center transition hover:border-emerald-400/40 hover:bg-emerald-500/10 disabled:opacity-60"
            >
              <span className="text-2xl" aria-hidden>
                🎥
              </span>
              <span className="text-sm font-medium text-white">
                {validating ? "Checking video…" : "Upload Video"}
              </span>
              <span className="text-xs text-gray-400">
                MP4 or MOV · up to {REEL_MAX_DURATION_LABEL}
              </span>
            </button>
          ) : (
            <div className="space-y-4">
              <div className="mx-auto w-full max-w-[220px] overflow-hidden rounded-xl border border-white/10 bg-black shadow-lg shadow-black/40">
                <video
                  src={previewUrl ?? undefined}
                  className="aspect-[9/16] w-full object-cover"
                  controls
                  playsInline
                  preload="metadata"
                />
              </div>

              <button
                type="button"
                disabled={publishing}
                onClick={() => fileInputRef.current?.click()}
                className="w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm text-gray-200 transition hover:bg-white/10 disabled:opacity-50"
              >
                Change video
              </button>

              <div>
                <label
                  htmlFor="reel-caption"
                  className="mb-1.5 block text-xs font-medium uppercase tracking-wide text-gray-400"
                >
                  Caption
                </label>
                <textarea
                  id="reel-caption"
                  value={caption}
                  onChange={(e) => setCaption(e.target.value)}
                  rows={3}
                  maxLength={2200}
                  placeholder="Write a caption…"
                  disabled={publishing}
                  className="w-full resize-none rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm text-white placeholder:text-gray-500 focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/30 disabled:opacity-60"
                />
              </div>
            </div>
          )}
        </>
      )}

      {errorMessage ? (
        <p className="mt-3 rounded-lg border border-red-500/30 bg-red-500/10 px-3 py-2 text-sm text-red-200">
          {errorMessage}
        </p>
      ) : null}
    </Modal>
  )
}
