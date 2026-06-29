"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import Modal from "@/app/components/ui/Modal"
import { supabase } from "@/lib/supabaseClient"
import { publishReel } from "@/lib/reels"
import {
  readReelVideoMetadata,
  validateReelVideoFile,
} from "@/lib/reelVideo"

type ReelComposerModalProps = {
  open: boolean
  userId: string | null
  onClose: () => void
  onPublished?: (reelId: string) => void
}

export default function ReelComposerModal({
  open,
  userId,
  onClose,
  onPublished,
}: ReelComposerModalProps) {
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
    if (!open) resetForm()
  }, [open, resetForm])

  const handleFileSelect = async (file: File | null) => {
    if (!file) return
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
    if (!userId || !videoFile || publishing) return

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

  return (
    <Modal
      open={open}
      onClose={handleClose}
      title="Create Reel"
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
          <button
            type="button"
            disabled={!videoFile || publishing || validating}
            onClick={() => void handlePublish()}
            className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-emerald-500 disabled:opacity-50"
          >
            {publishing ? "Publishing…" : "Publish"}
          </button>
        </div>
      }
    >
      <p className="mb-4 text-sm text-gray-400">
        Upload a vertical video up to 60 seconds (MP4 or MOV, max 100 MB).
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
          <span className="text-xs text-gray-400">MP4 or MOV · up to 60s</span>
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

      {errorMessage ? (
        <p className="mt-3 rounded-lg border border-red-500/30 bg-red-500/10 px-3 py-2 text-sm text-red-200">
          {errorMessage}
        </p>
      ) : null}
    </Modal>
  )
}
