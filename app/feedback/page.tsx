"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import ImageCropModal from "@/app/components/ImageCropModal"
import { useImageCropUpload } from "@/lib/useImageCropUpload"
import { useRouter } from "next/navigation"
import { supabase } from "../../lib/supabaseClient"
import { compressImage } from "@/lib/compressImage"
import { notifyAdminSubmission } from "@/lib/notifyAdminSubmission"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { USER_FACING_ERROR_MESSAGES } from "@/lib/userFacingError"
import {
  submissionFileBrowse,
  submissionFilePicker,
  submissionFormCard,
  submissionHistoryCard,
  submissionHistoryItem,
  submissionHistoryList,
  submissionInput,
  submissionLabel,
  submissionPageContainer,
  submissionPageShell,
  submissionStatusPill,
  submissionSubmitButton,
  submissionSubtitle,
  submissionTextarea,
  submissionTitle,
} from "@/lib/submissionFormStyles"
import { useUserProfile } from "@/lib/useUserProfile"

type FeedbackRow = {
  id: string
  subject: string | null
  message: string
  status: string | null
  created_at: string | null
}

function feedbackRowLabel(row: FeedbackRow): string {
  const subject = row.subject?.trim()
  if (subject) return subject
  const preview = row.message.trim().replace(/\s+/g, " ")
  if (!preview) return "Feedback"
  return preview.length > 80 ? `${preview.slice(0, 80)}…` : preview
}

export default function FeedbackPage() {
  const router = useRouter()
  const { user, loading: profileLoading } = useUserProfile()
  const [subject, setSubject] = useState("")
  const [message, setMessage] = useState("")
  const [image, setImage] = useState<File | null>(null)
  const [loading, setLoading] = useState(false)
  const submittingRef = useRef(false)
  const [success, setSuccess] = useState("")
  const [error, setError] = useState("")
  const imageCrop = useImageCropUpload({
    preset: "content",
    onCropped: setImage,
    onValidationError: setError,
  })
  const [history, setHistory] = useState<FeedbackRow[]>([])
  const [historyLoading, setHistoryLoading] = useState(true)

  const loadHistory = useCallback(async (userId: string) => {
    setHistoryLoading(true)
    const { data, error: qErr } = await supabase
      .from("feedback_submissions")
      .select("id, subject, message, status, created_at")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(25)

    if (qErr) {
      console.error("[feedback] history fetch failed", qErr)
      setHistory([])
    } else {
      setHistory((data as FeedbackRow[]) || [])
    }
    setHistoryLoading(false)
  }, [])

  useEffect(() => {
    if (profileLoading) return
    if (!user?.id) {
      setHistory([])
      setHistoryLoading(false)
      return
    }
    void loadHistory(user.id)
  }, [loadHistory, profileLoading, user?.id])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!message.trim() || submittingRef.current || loading) return

    submittingRef.current = true
    setLoading(true)
    setSuccess("")
    setError("")

    try {
      if (!user?.id) {
        router.push("/login")
        return
      }

      let screenshotUrl: string | null = null
      if (image) {
        let uploadFile: File = image
        if (image.type?.startsWith("image/")) {
          uploadFile = await compressImage(image)
        }
        const filePath = `feedback/${user.id}/${Date.now()}-${uploadFile.name}`
        const { error: uploadError } = await supabase.storage
          .from("screenshots")
          .upload(filePath, uploadFile, { upsert: false })

        if (uploadError) {
          console.error("[feedback] upload failed", uploadError)
          setError(
            handleSupabaseError(
              uploadError,
              USER_FACING_ERROR_MESSAGES.FILE_UPLOAD_FAILED
            )
          )
          return
        }

        const { data: publicData } = supabase.storage
          .from("screenshots")
          .getPublicUrl(filePath)
        screenshotUrl = publicData.publicUrl
      }

      const { data, error: insertError } = await supabase
        .from("feedback_submissions")
        .insert({
          user_id: user.id,
          email: user.email ?? null,
          subject: subject.trim() || null,
          message: message.trim(),
          screenshot_url: screenshotUrl,
          status: "open",
        })
        .select("id")
        .single()

      if (insertError) {
        console.error("[feedback] insert failed", insertError)
        setError(handleSupabaseError(insertError))
        return
      }

      if (data?.id) {
        notifyAdminSubmission("feedback_submission", data.id)
      }

      setSubject("")
      setMessage("")
      setImage(null)
      setSuccess("Feedback submitted. Thank you!")
      await loadHistory(user.id)
    } finally {
      submittingRef.current = false
      setLoading(false)
    }
  }

  return (
    <>
      <div className={submissionPageShell}>
        <div className={submissionPageContainer}>
          <form onSubmit={handleSubmit} className={submissionFormCard}>
            <h1 className={submissionTitle}>Send Feedback</h1>
            <p className={submissionSubtitle}>
              Tell us what you want changed or improved.
            </p>

            <label className={submissionLabel}>Subject (optional)</label>
            <input
              type="text"
              value={subject}
              onChange={(e) => setSubject(e.target.value)}
              placeholder="Short summary"
              className={submissionInput}
            />

            <label className={submissionLabel}>Message</label>
            <textarea
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              placeholder="What should we change?"
              rows={6}
              className={submissionTextarea}
            />

            <label className={submissionLabel}>Screenshot (optional)</label>
            <label className={submissionFilePicker}>
              <span className="truncate">{image ? image.name : "Choose an image..."}</span>
              <span className={submissionFileBrowse}>Browse</span>
              <input
                type="file"
                accept="image/*"
                onChange={(e) => imageCrop.handleFileSelected(e.target.files?.[0])}
                className="hidden"
              />
            </label>

            {error ? <p className="mb-3 text-sm text-red-300">{error}</p> : null}
            {success ? <p className="mb-3 text-sm text-emerald-300">{success}</p> : null}

            <button
              type="submit"
              disabled={loading || !message.trim()}
              className={submissionSubmitButton}
            >
              {loading ? "Submitting..." : "Submit Feedback"}
            </button>
          </form>

          <section className={submissionHistoryCard}>
            <h2 className="text-lg font-semibold text-white">Your recent feedback</h2>
            <p className="mt-1 text-sm text-gray-400">
              Subject, status, and date for feedback you submitted.
            </p>
            {historyLoading ? (
              <p className="mt-4 text-sm text-gray-400">Loading...</p>
            ) : !history.length ? (
              <p className="mt-4 text-sm text-gray-400">No feedback submitted yet.</p>
            ) : (
              <ul className={submissionHistoryList}>
                {history.map((row) => (
                  <li key={row.id} className={submissionHistoryItem}>
                    <span className="font-medium text-gray-100">{feedbackRowLabel(row)}</span>
                    <div className="flex flex-wrap items-center gap-2 text-xs text-gray-400">
                      <span className={submissionStatusPill}>
                        {row.status || "open"}
                      </span>
                      <span className="tabular-nums">
                        {row.created_at
                          ? new Date(row.created_at).toLocaleString()
                          : "—"}
                      </span>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>
      </div>
      <ImageCropModal
        open={imageCrop.cropSourceFile != null}
        file={imageCrop.cropSourceFile}
        preset="content"
        onCancel={imageCrop.handleCropCancel}
        onSave={imageCrop.handleCropSave}
      />
    </>
  )
}
