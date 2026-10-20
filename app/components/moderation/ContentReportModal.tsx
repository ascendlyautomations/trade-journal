"use client"

import { useCallback, useState } from "react"
import {
  CONTENT_REPORT_REASONS,
  contentReportReasonLabel,
  type ContentReportReason,
} from "@/lib/contentReports"
import { submitContentReport } from "@/lib/submitContentReport"
import type { ContentReportRequest } from "@/lib/feedContentReport"

type ContentReportModalProps = {
  open: boolean
  request: ContentReportRequest | null
  onClose: () => void
  onBlockUser?: (userId: string) => Promise<void>
}

type Phase =
  | { kind: "form" }
  | { kind: "submitting" }
  | { kind: "success"; duplicate: boolean }
  | { kind: "error"; message: string }

export default function ContentReportModal({
  open,
  request,
  onClose,
  onBlockUser,
}: ContentReportModalProps) {
  const [reason, setReason] = useState<ContentReportReason | null>(null)
  const [details, setDetails] = useState("")
  const [phase, setPhase] = useState<Phase>({ kind: "form" })
  const [blockBusy, setBlockBusy] = useState(false)
  const [blockError, setBlockError] = useState<string | null>(null)

  const reset = useCallback(() => {
    setReason(null)
    setDetails("")
    setPhase({ kind: "form" })
    setBlockBusy(false)
    setBlockError(null)
  }, [])

  const handleClose = useCallback(() => {
    reset()
    onClose()
  }, [onClose, reset])

  if (!open || !request) return null

  const showsDetails = reason === "other"
  const canSubmit = reason != null && (reason !== "other" || details.trim().length > 0)

  async function handleSubmit() {
    if (!request || !reason) return
    setPhase({ kind: "submitting" })
    const result = await submitContentReport({
      targetType: request.targetType,
      targetId: request.targetId,
      reportedUserId: request.reportedUserId,
      reason,
      details: showsDetails ? details.trim() : null,
    })
    if (!result.ok) {
      setPhase({ kind: "error", message: result.message })
      return
    }
    setPhase({ kind: "success", duplicate: result.duplicate === true })
  }

  async function handleBlock() {
    if (!request?.blockUserId || !onBlockUser) return
    setBlockBusy(true)
    setBlockError(null)
    try {
      await onBlockUser(request.blockUserId)
      handleClose()
    } catch (error) {
      setBlockError(
        error instanceof Error ? error.message : "Could not block this user."
      )
    } finally {
      setBlockBusy(false)
    }
  }

  return (
    <div
      className="fixed inset-0 z-[9200] flex items-end justify-center bg-black/60 p-4 sm:items-center"
      role="dialog"
      aria-modal="true"
      aria-labelledby="content-report-title"
      onClick={handleClose}
    >
      <div
        className="max-h-[90vh] w-full max-w-md overflow-y-auto rounded-xl border border-white/10 bg-[#0b1220] p-5 shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        {phase.kind === "form" || phase.kind === "submitting" ? (
          <>
            <h2 id="content-report-title" className="text-lg font-semibold text-white">
              Report
            </h2>
            <p className="mt-1 text-sm text-gray-400">
              Reporting {request.subjectTitle}
            </p>
            <p className="mt-2 text-xs text-gray-500">
              Reports are reviewed under the TradeTraxs Community Guidelines.
            </p>

            <p className="mt-4 text-xs font-semibold uppercase tracking-wide text-gray-400">
              Why are you reporting this?
            </p>
            <ul className="mt-2 space-y-1">
              {CONTENT_REPORT_REASONS.map((value) => (
                <li key={value}>
                  <button
                    type="button"
                    disabled={phase.kind === "submitting"}
                    onClick={() => setReason(value)}
                    className={`flex w-full items-center justify-between rounded-lg px-3 py-2 text-left text-sm ${
                      reason === value
                        ? "bg-blue-500/20 text-white"
                        : "text-gray-200 hover:bg-white/5"
                    }`}
                  >
                    {contentReportReasonLabel(value)}
                    {reason === value ? (
                      <span className="text-blue-300" aria-hidden>
                        ✓
                      </span>
                    ) : null}
                  </button>
                </li>
              ))}
            </ul>

            {showsDetails ? (
              <label className="mt-3 block">
                <span className="text-xs font-semibold text-gray-400">
                  Additional details
                </span>
                <textarea
                  value={details}
                  onChange={(e) => setDetails(e.target.value)}
                  rows={3}
                  className="mt-1 w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white"
                  placeholder="Describe the issue…"
                />
              </label>
            ) : null}

            <div className="mt-5 flex flex-col gap-2 sm:flex-row sm:justify-end">
              <button
                type="button"
                className="rounded-lg border border-white/10 px-4 py-2 text-sm text-gray-200 hover:bg-white/5"
                onClick={handleClose}
                disabled={phase.kind === "submitting"}
              >
                Cancel
              </button>
              <button
                type="button"
                className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
                disabled={!canSubmit || phase.kind === "submitting"}
                onClick={() => void handleSubmit()}
              >
                {phase.kind === "submitting" ? "Submitting…" : "Submit report"}
              </button>
            </div>
          </>
        ) : null}

        {phase.kind === "success" ? (
          <div className="text-center">
            <p className="text-lg font-semibold text-white">
              {phase.duplicate ? "Already reported" : "Report submitted"}
            </p>
            <p className="mt-2 text-sm text-gray-400">
              {phase.duplicate
                ? "You already reported this content. Our team will review it."
                : "Thanks — the TradeTraxs team will review your report."}
            </p>
            {request.blockUserId && onBlockUser ? (
              <div className="mt-4 space-y-2">
                <button
                  type="button"
                  className="w-full rounded-lg border border-red-500/40 px-4 py-2 text-sm font-semibold text-red-300 hover:bg-red-500/10 disabled:opacity-50"
                  disabled={blockBusy}
                  onClick={() => void handleBlock()}
                >
                  {blockBusy ? "Blocking…" : "Block this user"}
                </button>
                {blockError ? (
                  <p className="text-xs text-amber-400">{blockError}</p>
                ) : null}
              </div>
            ) : null}
            <button
              type="button"
              className="mt-4 w-full rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white"
              onClick={handleClose}
            >
              Done
            </button>
          </div>
        ) : null}

        {phase.kind === "error" ? (
          <div className="text-center">
            <p className="text-lg font-semibold text-white">Couldn&apos;t submit report</p>
            <p className="mt-2 text-sm text-gray-400">{phase.message}</p>
            <button
              type="button"
              className="mt-4 w-full rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white"
              onClick={() => setPhase({ kind: "form" })}
            >
              Try again
            </button>
          </div>
        ) : null}
      </div>
    </div>
  )
}
