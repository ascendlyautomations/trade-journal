"use client"

import { createPortal } from "react-dom"
import { useEffect, useMemo, useState } from "react"
import type { UploadJob } from "@/lib/uploadProgress/types"

type UploadManagerProps = {
  jobs: UploadJob[]
  expanded: boolean
  onToggleExpanded: () => void
}

function activeUploadCount(jobs: UploadJob[]): number {
  return jobs.filter(
    (job) => job.status === "running" || job.status === "queued"
  ).length
}

function UploadJobRow({ job }: { job: UploadJob }) {
  const isSuccess = job.status === "success"
  const isError = job.status === "error"
  const isQueued = job.status === "queued"

  return (
    <div className="border-t border-white/10 px-4 py-3 first:border-t-0">
      <div className="mb-2 flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate text-sm font-medium text-white">{job.title}</p>
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
            className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-emerald-500/20 text-xs text-emerald-300"
            aria-hidden
          >
            ✓
          </span>
        ) : isQueued ? (
          <span className="shrink-0 text-[10px] font-medium uppercase tracking-wide text-gray-400">
            Queued
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
                : isQueued
                  ? "bg-white/20"
                  : "bg-violet-400"
          }`}
          style={{
            width: `${Math.max(0, Math.min(100, isQueued ? 0 : job.percent))}%`,
          }}
        />
      </div>

      {isError ? (
        <div className="mt-2.5 flex gap-2">
          <button
            type="button"
            onClick={() => job.retry?.()}
            className="flex-1 rounded-lg bg-violet-600 px-2.5 py-1.5 text-xs font-medium text-white transition hover:bg-violet-500"
          >
            Retry
          </button>
          <button
            type="button"
            onClick={() => job.cancel?.()}
            className="flex-1 rounded-lg border border-white/15 bg-white/5 px-2.5 py-1.5 text-xs font-medium text-gray-200 transition hover:bg-white/10"
          >
            Cancel
          </button>
        </div>
      ) : null}
    </div>
  )
}

export default function UploadManager({
  jobs,
  expanded,
  onToggleExpanded,
}: UploadManagerProps) {
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
  }, [])

  const activeCount = useMemo(() => activeUploadCount(jobs), [jobs])

  if (!mounted || jobs.length === 0) return null

  const headerLabel =
    activeCount > 0 ? `Uploading (${activeCount})` : `Uploads (${jobs.length})`

  return createPortal(
    <div
        className="pointer-events-none fixed inset-x-3 bottom-[max(0.75rem,calc(var(--safe-area-bottom)+var(--app-tab-bar-height)))] z-[199000] sm:inset-x-auto sm:bottom-4 sm:right-4 sm:w-full sm:max-w-sm"
      role="region"
      aria-label="Upload manager"
    >
      <div className="pointer-events-auto overflow-hidden rounded-2xl border border-white/10 bg-[#0b1f3a]/95 shadow-2xl shadow-black/40 backdrop-blur-md">
        <button
          type="button"
          onClick={onToggleExpanded}
          className="flex w-full items-center justify-between gap-3 px-4 py-3 text-left transition hover:bg-white/[0.04]"
          aria-expanded={expanded}
        >
          <span className="flex min-w-0 items-center gap-2 text-sm font-semibold text-white">
            <span
              className={`text-xs text-gray-400 transition-transform ${
                expanded ? "rotate-180" : ""
              }`}
              aria-hidden
            >
              ⬆
            </span>
            <span className="truncate">{headerLabel}</span>
          </span>
          {!expanded && activeCount > 0 ? (
            <span className="shrink-0 text-xs tabular-nums text-gray-400">
              {jobs.find((job) => job.status === "running")?.percent ?? 0}%
            </span>
          ) : null}
        </button>

        {expanded ? (
          <div className="max-h-[min(50vh,320px)] overflow-y-auto border-t border-white/10">
            {jobs.map((job) => (
              <UploadJobRow key={job.id} job={job} />
            ))}
          </div>
        ) : null}
      </div>
    </div>,
    document.body
  )
}
