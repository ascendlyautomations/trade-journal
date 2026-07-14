"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import {
  BUG_REPORT_SEVERITY_OPTIONS,
  captureBrowserInfo,
  capturePageUrl,
  submitBugReport,
  type BugReportSeverity,
} from "@/lib/bugReports"
import {
  submissionFileBrowse,
  submissionFilePicker,
  submissionFormCard,
  submissionInput,
  submissionLabel,
  submissionSelect,
  submissionSubmitButton,
  submissionSubtitle,
  submissionTextarea,
  submissionTitle,
} from "@/lib/submissionFormStyles"
import ModalCloseButton from "@/app/components/ui/ModalCloseButton"
import CustomSelect from "@/app/components/CustomSelect"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import ImageCropModal from "@/app/components/ImageCropModal"
import { useImageCropUpload } from "@/lib/useImageCropUpload"
import { useUserProfile } from "@/lib/useUserProfile"

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
  const { user } = useUserProfile()
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
  useModalScrollLock(open)
  const imageCrop = useImageCropUpload({
    preset: "content",
    onCropped: setScreenshot,
    onValidationError: setError,
  })
  const fileInputRef = imageCrop.fileInputRef

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
    if (!user?.id) {
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
      className="fixed inset-0 z-[10050] flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm"
      onClick={() => {
        if (!busy && !success) onClose()
      }}
    >
      <div
        className={`max-h-[90vh] w-full max-w-lg overflow-y-auto ${submissionFormCard}`}
        role="dialog"
        aria-modal="true"
        aria-labelledby="bug-report-title"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-start justify-between gap-3">
          <div className="min-w-0 flex-1">
            <h2 id="bug-report-title" className={submissionTitle}>
              Report a bug
            </h2>
            <p className={`${submissionSubtitle} mb-0 mt-2 text-left`}>
              Help us improve TradeTraxs. Page and browser details are captured
              automatically.
            </p>
          </div>
          <ModalCloseButton onClick={onClose} disabled={busy || success} />
        </div>

        {success ? (
          <p className="rounded-lg border border-emerald-400/30 bg-emerald-500/10 px-4 py-3 text-sm text-emerald-200">
            Thanks. Your report was submitted.
          </p>
        ) : (
          <form className="space-y-1" onSubmit={(e) => void handleSubmit(e)}>
            <label className={submissionLabel} htmlFor="bug-title">
              Title
            </label>
            <input
              id="bug-title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              required
              maxLength={200}
              disabled={busy}
              className={submissionInput}
              placeholder="Short summary of the issue"
            />

            <label className={submissionLabel} htmlFor="bug-description">
              Description
            </label>
            <textarea
              id="bug-description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              required
              rows={5}
              disabled={busy}
              className={submissionTextarea}
              placeholder="What happened? What did you expect? Steps to reproduce?"
            />

            <label className={submissionLabel} htmlFor="bug-severity">
              Severity
            </label>
            <CustomSelect
              id="bug-severity"
              value={severity}
              onChange={(val) => setSeverity(val as BugReportSeverity)}
              disabled={busy}
              triggerClassName={submissionSelect}
              options={BUG_REPORT_SEVERITY_OPTIONS.map((opt) => ({
                label: opt.label,
                value: opt.value,
              }))}
            />

            <label className={submissionLabel} htmlFor="bug-screenshot">
              Screenshot (optional)
            </label>
            <label className={submissionFilePicker}>
              <span className="truncate">
                {screenshot ? screenshot.name : "Choose an image..."}
              </span>
              <span className={submissionFileBrowse}>Browse</span>
              <input
                ref={fileInputRef}
                id="bug-screenshot"
                type="file"
                accept="image/*"
                disabled={busy || success}
                onChange={(e) => imageCrop.handleFileSelected(e.target.files?.[0])}
                className="hidden"
              />
            </label>

            <div className="mb-4 rounded-xl border border-white/10 bg-black/20 px-4 py-3 text-xs text-gray-500">
              <p>
                <span className="text-gray-400">Page:</span> {pageUrl || "—"}
              </p>
              <p className="mt-1 break-all">
                <span className="text-gray-400">Browser:</span> {browserInfo || "—"}
              </p>
            </div>

            {error ? (
              <p className="mb-3 rounded-lg border border-red-400/30 bg-red-500/10 px-3 py-2 text-sm text-red-200">
                {error}
              </p>
            ) : null}

            <div className="flex flex-col-reverse gap-2 pt-1 sm:flex-row sm:justify-end">
              <button
                type="button"
                onClick={onClose}
                disabled={busy || success}
                className="rounded-xl border border-white/15 bg-white/5 px-4 py-2.5 text-sm font-medium text-gray-200 transition hover:bg-white/10 disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={busy || success || !title.trim() || !description.trim()}
                className={`${submissionSubmitButton} sm:w-auto sm:min-w-[10rem] sm:px-6`}
              >
                {busy && !success ? "Submitting…" : "Submit report"}
              </button>
            </div>
          </form>
        )}
      </div>
      <ImageCropModal
        open={imageCrop.cropSourceFile != null}
        file={imageCrop.cropSourceFile}
        preset="content"
        onCancel={imageCrop.handleCropCancel}
        onSave={imageCrop.handleCropSave}
      />
    </div>
  )
}
