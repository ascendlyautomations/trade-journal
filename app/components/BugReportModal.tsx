"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "@/lib/supabaseClient"
import {
  BUG_REPORT_SEVERITY_OPTIONS,
  captureBrowserInfo,
  capturePageUrl,
  submitBugReport,
  type BugReportSeverity,
} from "@/lib/bugReports"

const SUCCESS_AUTO_CLOSE_MS = 1000

type BugReportModalProps = {
  open: boolean
  onClose: () => void
  onSubmitted?: () => void
}

export default function BugReportModal({
  open,
  onClose,
  onSubmitted,
}: BugReportModalProps) {
  const router = useRouter()
  const fileInputRef = useRef<HTMLInputElement>(null)
  const submittingRef = useRef(false)
  const [title, setTitle] = useState("")
  const [description, setDescription] = useState("")
  const [severity, setSeverity] = useState<BugReportSeverity>("medium")
  const [screenshot, setScreenshot] = useState<File | null>(null)
  const [pageUrl, setPageUrl] = useState("")
  const [browserInfo, setBrowserInfo] = useState("")
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState(false)

  const resetForm = useCallback(() => {
    setTitle("")
    setDescription("")
    setSeverity("medium")
    setScreenshot(null)
    setError(null)
    setSuccess(false)
    setBusy(false)
    if (fileInputRef.current) {
      fileInputRef.current.value = ""
    }
  }, [])

  useEffect(() => {
    if (!open) {
      resetForm()
      return
    }
    resetForm()
    setPageUrl(capturePageUrl())
    setBrowserInfo(captureBrowserInfo())
  }, [open, resetForm])

  useEffect(() => {
    if (!success) return
    const timer = window.setTimeout(() => {
      resetForm()
      onClose()
    }, SUCCESS_AUTO_CLOSE_MS)
    return () => window.clearTimeout(timer)
  }, [success, onClose, resetForm])

  useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape" && !busy && !success) onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, busy, success, onClose])

  if (!open) return null

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (submittingRef.current || busy || success) return

    submittingRef.current = true
    setBusy(true)
    setError(null)

    try {
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser()

    if (authError || !user) {
      onClose()
      router.push("/login")
      return
    }

    const result = await submitBugReport(user.id, {
      title,
      description,
      severity,
      screenshotFile: screenshot,
      pageUrl,
      browserInfo,
    })

    if (!result.ok) {
      setError(result.message)
      setBusy(false)
      return
    }

    setSuccess(true)
    onSubmitted?.()
    } finally {
      submittingRef.current = false
    }
  }

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm"
      onClick={() => {
        if (!busy && !success) onClose()
      }}
    >
      <div
        className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl border border-white/10 bg-[#152238] p-6 text-white shadow-2xl"
        role="dialog"
        aria-modal="true"
        aria-labelledby="bug-report-title"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-start justify-between gap-3">
          <div>
            <h2 id="bug-report-title" className="text-lg font-semibold text-white">
              Report a bug
            </h2>
            <p className="mt-1 text-sm text-gray-400">
              Help us improve TradeTraxs during beta. Page and browser details are captured
              automatically.
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            disabled={busy || success}
            className="rounded px-2 py-1 text-gray-400 hover:bg-white/10 hover:text-white disabled:opacity-50"
            aria-label="Close"
          >
            ✕
          </button>
        </div>

        {success ? (
          <p className="rounded-lg border border-emerald-400/30 bg-emerald-500/10 px-4 py-3 text-sm text-emerald-200">
            Thanks — your report was submitted.
          </p>
        ) : (
          <form className="space-y-4" onSubmit={(e) => void handleSubmit(e)}>
            <div>
              <label className="mb-1 block text-sm text-gray-300" htmlFor="bug-title">
                Title
              </label>
              <input
                id="bug-title"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                required
                maxLength={200}
                disabled={busy}
                className="w-full rounded-lg border border-white/10 bg-[#0f172a] px-3 py-2 text-sm text-white outline-none ring-blue-500/40 focus:ring-2 disabled:opacity-50"
                placeholder="Short summary of the issue"
              />
            </div>

            <div>
              <label className="mb-1 block text-sm text-gray-300" htmlFor="bug-description">
                Description
              </label>
              <textarea
                id="bug-description"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                required
                rows={5}
                disabled={busy}
                className="w-full resize-y rounded-lg border border-white/10 bg-[#0f172a] px-3 py-2 text-sm text-white outline-none ring-blue-500/40 focus:ring-2 disabled:opacity-50"
                placeholder="What happened? What did you expect? Steps to reproduce?"
              />
            </div>

            <div>
              <label className="mb-1 block text-sm text-gray-300" htmlFor="bug-severity">
                Severity
              </label>
              <select
                id="bug-severity"
                value={severity}
                onChange={(e) => setSeverity(e.target.value as BugReportSeverity)}
                disabled={busy}
                className="w-full rounded-lg border border-white/10 bg-[#0f172a] px-3 py-2 text-sm text-white outline-none ring-blue-500/40 focus:ring-2 disabled:opacity-50"
              >
                {BUG_REPORT_SEVERITY_OPTIONS.map((opt) => (
                  <option key={opt.value} value={opt.value}>
                    {opt.label}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="mb-1 block text-sm text-gray-300" htmlFor="bug-screenshot">
                Screenshot (optional)
              </label>
              <input
                ref={fileInputRef}
                id="bug-screenshot"
                type="file"
                accept="image/*"
                disabled={busy || success}
                onChange={(e) => setScreenshot(e.target.files?.[0] ?? null)}
                className="block w-full text-sm text-gray-300 file:mr-3 file:rounded file:border-0 file:bg-white/10 file:px-3 file:py-1.5 file:text-sm file:text-gray-100"
              />
            </div>

            <div className="rounded-lg border border-white/5 bg-black/20 px-3 py-2 text-xs text-gray-500">
              <p>
                <span className="text-gray-400">Page:</span> {pageUrl || "—"}
              </p>
              <p className="mt-1 break-all">
                <span className="text-gray-400">Browser:</span> {browserInfo || "—"}
              </p>
            </div>

            {error ? (
              <p className="rounded-lg border border-red-400/30 bg-red-500/10 px-3 py-2 text-sm text-red-200">
                {error}
              </p>
            ) : null}

            <div className="flex justify-end gap-2 pt-1">
              <button
                type="button"
                onClick={onClose}
                disabled={busy || success}
                className="rounded-lg border border-white/10 px-4 py-2 text-sm text-gray-200 hover:bg-white/5 disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={busy || success || !title.trim() || !description.trim()}
                className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-medium text-white hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-50"
              >
                {busy && !success ? "Submitting…" : "Submit report"}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  )
}
