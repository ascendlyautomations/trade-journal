"use client"

import { createPortal } from "react-dom"
import { useEffect, useState } from "react"
import type { UploadJob } from "@/lib/uploadProgress/types"
import { useMobileWebSheetDismiss } from "@/lib/useMobileWebSheetDismiss"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import { UI_MODAL_BACKDROP } from "@/lib/uiPrimitiveStyles"

type Props = {
  open: boolean
  onClose: () => void
  jobs: UploadJob[]
}

function UploadQueueJobRow({ job }: { job: UploadJob }) {
  const isSuccess = job.status === "success"
  const isError = job.status === "error"
  const isQueued = job.status === "queued"

  return (
    <div className="border-b border-white/10 px-4 py-3 last:border-b-0">
      <div className="mb-2 flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate text-sm font-medium text-[color:var(--tt-text,#f0f3f6)]">
            {job.title}
          </p>
          <p
            className={`mt-0.5 truncate text-xs ${
              isError ? "text-red-300" : "text-[color:var(--tt-text-muted,#c0cad6)]"
            }`}
          >
            {isError ? job.errorMessage ?? job.stage : job.stage}
          </p>
        </div>
        {isSuccess ? (
          <span className="text-xs font-semibold text-emerald-400">Done</span>
        ) : isQueued ? (
          <span className="text-[10px] font-medium uppercase tracking-wide text-[color:var(--tt-text-tertiary,#a8b3c2)]">
            Queued
          </span>
        ) : (
          <span className="shrink-0 text-xs tabular-nums text-[color:var(--tt-text-muted,#c0cad6)]">
            {job.percent}%
          </span>
        )}
      </div>
      <div className="h-1 overflow-hidden rounded-full bg-white/10">
        <div
          className={`h-full rounded-full transition-[width] duration-300 ${
            isError
              ? "bg-red-400/80"
              : isSuccess
                ? "bg-emerald-400"
                : isQueued
                  ? "bg-white/20"
                  : "bg-[color:var(--tt-accent,#4ec4e0)]"
          }`}
          style={{
            width: `${Math.max(0, Math.min(100, isQueued ? 0 : job.percent))}%`,
          }}
        />
      </div>
      {isError ? (
        <div className="mt-2.5 flex gap-2">
          {job.retry ? (
            <button
              type="button"
              onClick={() => job.retry?.()}
              className="flex-1 rounded-xl bg-[color:var(--tt-accent,#4ec4e0)] px-2.5 py-2 text-xs font-semibold text-[#0d1117]"
            >
              Retry
            </button>
          ) : null}
          {job.cancel ? (
            <button
              type="button"
              onClick={() => job.cancel?.()}
              className="flex-1 rounded-xl border border-white/15 px-2.5 py-2 text-xs font-semibold text-[color:var(--tt-text,#f0f3f6)]"
            >
              Remove
            </button>
          ) : null}
        </div>
      ) : null}
    </div>
  )
}

export default function MobileWebGlobalUploadQueueSheet({
  open,
  onClose,
  jobs,
}: Props) {
  const [mounted, setMounted] = useState(false)
  const dismiss = useMobileWebSheetDismiss(onClose)

  useEffect(() => setMounted(true), [])
  useModalScrollLock(open)

  if (!open || !mounted) return null

  return createPortal(
    <div
      className="fixed inset-0 z-[10065] md:hidden"
      role="presentation"
      onClick={onClose}
    >
      <div className={UI_MODAL_BACKDROP} aria-hidden />
      <div
        role="dialog"
        aria-modal="true"
        aria-label="Uploads"
        className="absolute inset-x-0 bottom-0 flex max-h-[min(85vh,520px)] flex-col overflow-hidden rounded-t-2xl border border-white/10 bg-[color:var(--tt-surface-nested,#1a222c)] text-white shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div {...dismiss}>
          <div className="flex justify-center pt-3 pb-1">
            <div className="h-1 w-10 rounded-full bg-white/20" aria-hidden />
          </div>
        </div>
        <div className="border-b border-white/10 px-4 pb-3">
          <h2 className="text-base font-semibold">Uploads</h2>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto">
          {jobs.map((job) => (
            <UploadQueueJobRow key={job.id} job={job} />
          ))}
        </div>
        <div className="border-t border-white/10 p-4">
          <button
            type="button"
            className="w-full rounded-xl bg-white/10 px-4 py-2.5 text-sm font-semibold"
            onClick={onClose}
          >
            Done
          </button>
        </div>
      </div>
    </div>,
    document.body
  )
}
