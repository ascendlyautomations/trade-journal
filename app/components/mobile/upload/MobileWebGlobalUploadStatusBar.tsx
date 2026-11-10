"use client"

import { useEffect } from "react"
import { useUploadProgress } from "@/lib/uploadProgress/UploadProgressProvider"
import { buildGlobalUploadBarPresentation } from "@/lib/uploadProgress/globalUploadBarPresentation"
import { usePhoneWebTouchTarget } from "@/lib/usePhoneWebTouchTarget"
import MobileWebGlobalUploadQueueSheet from "./MobileWebGlobalUploadQueueSheet"
import { useState } from "react"

export default function MobileWebGlobalUploadStatusBar() {
  const phoneWeb = usePhoneWebTouchTarget()
  const { jobs } = useUploadProgress()
  const [queueOpen, setQueueOpen] = useState(false)
  const presentation = buildGlobalUploadBarPresentation(jobs)

  useEffect(() => {
    if (!phoneWeb) return
    const active = Boolean(presentation)
    document.documentElement.classList.toggle("tt-mobile-web-upload-bar", active)
    return () => {
      document.documentElement.classList.remove("tt-mobile-web-upload-bar")
    }
  }, [phoneWeb, presentation])

  if (!phoneWeb || !presentation) return null

  const onRetry = () => {
    if (presentation.retryJobId) {
      const job = jobs.find((j) => j.id === presentation.retryJobId)
      job?.retry?.()
      return
    }
    const failed = jobs.find((j) => j.status === "error" && j.retry)
    failed?.retry?.()
  }

  return (
    <>
      <div
        className="fixed inset-x-0 top-[var(--app-header-offset)] z-[9996] border-b border-white/10 bg-[color:var(--tt-navbar,#0b1f3a)]/98 md:hidden"
        data-tt-mobile-web-upload-bar=""
        role="status"
        aria-live="polite"
      >
        <div className="flex items-stretch">
          <button
            type="button"
            className="min-w-0 flex-1 px-4 py-2.5 text-left"
            onClick={() => {
              if (presentation.showsRetry && !presentation.retryJobId) {
                onRetry()
                return
              }
              setQueueOpen(true)
            }}
          >
            <div className="flex items-center gap-2">
              <span className="min-w-0 flex-1 truncate text-sm font-medium text-[color:var(--tt-text,#f0f3f6)]">
                {presentation.line}
              </span>
              {presentation.showsRetry && !presentation.retryJobId ? (
                <span className="shrink-0 text-sm font-semibold text-[color:var(--tt-accent,#4ec4e0)]">
                  Retry
                </span>
              ) : null}
            </div>
            {presentation.progress != null ? (
              <div className="mt-1.5 h-1 overflow-hidden rounded-full bg-white/10">
                <div
                  className="h-full rounded-full bg-[color:var(--tt-accent,#4ec4e0)] transition-[width] duration-300"
                  style={{ width: `${Math.round(presentation.progress * 100)}%` }}
                />
              </div>
            ) : presentation.activeCount > 0 &&
              jobs.some((j) => j.status === "running" || j.status === "queued") ? (
              <div className="mt-1.5 h-1 overflow-hidden rounded-full bg-white/10">
                <div className="h-full w-1/3 animate-pulse rounded-full bg-[color:var(--tt-accent,#4ec4e0)]/60" />
              </div>
            ) : null}
          </button>
          {presentation.showsRetry && presentation.retryJobId ? (
            <button
              type="button"
              className="shrink-0 self-center px-4 text-sm font-semibold text-[color:var(--tt-accent,#4ec4e0)]"
              onClick={onRetry}
            >
              Retry
            </button>
          ) : null}
        </div>
      </div>
      <MobileWebGlobalUploadQueueSheet
        open={queueOpen}
        onClose={() => setQueueOpen(false)}
        jobs={jobs}
      />
    </>
  )
}
