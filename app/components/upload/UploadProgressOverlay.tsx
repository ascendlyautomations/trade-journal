"use client"

import { createPortal } from "react-dom"
import { useEffect, useState } from "react"
import type { UploadJob } from "@/lib/uploadProgress/types"

type UploadProgressOverlayProps = {
  job: UploadJob | null
  onDismiss: () => void
}

export default function UploadProgressOverlay({
  job,
  onDismiss,
}: UploadProgressOverlayProps) {
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
  }, [])

  if (!mounted || !job) return null

  const isSuccess = job.status === "success"
  const isError = job.status === "error"

  return createPortal(
    <div className="pointer-events-none fixed inset-x-0 bottom-6 z-[200000] flex justify-center px-4 sm:bottom-8">
      <div
        className="pointer-events-auto w-full max-w-sm rounded-2xl border border-white/10 bg-[#0b1f3a]/95 px-4 py-4 shadow-2xl shadow-black/40 backdrop-blur-md"
        role="status"
        aria-live="polite"
        aria-label={job.title}
      >
        <div className="mb-2 flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold text-white">
              {job.title}
            </p>
            <p
              className={`mt-0.5 truncate text-xs ${
                isError ? "text-red-300" : "text-gray-400"
              }`}
            >
              {isError ? job.errorMessage ?? job.stage : job.stage}
            </p>
          </div>
          {isSuccess ? (
            <span
              className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-emerald-500/20 text-sm text-emerald-300"
              aria-hidden
            >
              ✓
            </span>
          ) : (
            <span className="shrink-0 text-xs font-medium tabular-nums text-gray-300">
              {job.percent}%
            </span>
          )}
        </div>

        <div className="h-1.5 overflow-hidden rounded-full bg-white/10">
          <div
            className={`h-full rounded-full transition-[width] duration-300 ease-out ${
              isError
                ? "bg-red-400/80"
                : isSuccess
                  ? "bg-emerald-400"
                  : "bg-violet-400"
            }`}
            style={{ width: `${Math.max(0, Math.min(100, job.percent))}%` }}
          />
        </div>

        {isError ? (
          <div className="mt-3 flex gap-2">
            <button
              type="button"
              onClick={() => job.retry?.()}
              className="flex-1 rounded-lg bg-violet-600 px-3 py-2 text-xs font-medium text-white transition hover:bg-violet-500"
            >
              Retry
            </button>
            <button
              type="button"
              onClick={() => {
                job.cancel?.()
                onDismiss()
              }}
              className="flex-1 rounded-lg border border-white/15 bg-white/5 px-3 py-2 text-xs font-medium text-gray-200 transition hover:bg-white/10"
            >
              Cancel
            </button>
          </div>
        ) : null}
      </div>
    </div>,
    document.body
  )
}
