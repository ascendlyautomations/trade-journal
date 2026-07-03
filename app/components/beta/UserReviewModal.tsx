"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import Modal from "@/app/components/ui/Modal"
import StarRatingInput from "@/app/components/beta/StarRatingInput"
import { supabase } from "@/lib/supabaseClient"
import {
  fetchMyUserReview,
  saveUserReview,
  type UserReviewRow,
} from "@/lib/userReviews"
import {
  submissionInput,
  submissionLabel,
  submissionSubmitButton,
  submissionTextarea,
} from "@/lib/submissionFormStyles"
import { useUserProfile } from "@/lib/useUserProfile"

const REVIEW_MIN = 50
const REVIEW_MAX = 400

type UserReviewModalProps = {
  open: boolean
  userId: string | null
  onClose: () => void
  onSaved?: (row: UserReviewRow) => void
}

export default function UserReviewModal({
  open,
  userId,
  onClose,
  onSaved,
}: UserReviewModalProps) {
  const router = useRouter()
  const { user, profile } = useUserProfile()
  const submittingRef = useRef(false)
  const [loading, setLoading] = useState(false)
  const [existing, setExisting] = useState<UserReviewRow | null>(null)
  const [rating, setRating] = useState(5)
  const [title, setTitle] = useState("")
  const [review, setReview] = useState("")
  const [wouldRecommend, setWouldRecommend] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState(false)

  const resetForm = useCallback(() => {
    setRating(5)
    setTitle("")
    setReview("")
    setWouldRecommend(true)
    setExisting(null)
    setError(null)
    setSuccess(false)
    setBusy(false)
    setLoading(false)
  }, [])

  useEffect(() => {
    if (!open) {
      resetForm()
      return
    }

    resetForm()

    if (!userId) return

    let cancelled = false
    setLoading(true)

    void (async () => {
      const { data: row, error: fetchError } = await fetchMyUserReview(userId)
      if (cancelled) return

      if (fetchError) {
        setError("Could not load your review. Please refresh and try again.")
        setLoading(false)
        return
      }

      if (row) {
        setExisting(row)
        setRating(row.rating)
        setTitle(row.title ?? "")
        setReview(row.review)
        setWouldRecommend(row.would_recommend)
      }

      setLoading(false)
    })()

    return () => {
      cancelled = true
    }
  }, [open, resetForm, userId])

  useEffect(() => {
    if (!success) return
    const timer = window.setTimeout(() => {
      onClose()
    }, 1200)
    return () => window.clearTimeout(timer)
  }, [success, onClose])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (submittingRef.current || busy || success || loading) return

    submittingRef.current = true
    setBusy(true)
    setError(null)

    try {
      const authUserId = userId ?? user?.id
      if (!authUserId) {
        onClose()
        router.push("/login")
        return
      }

      if (!profile?.username) {
        setError("Could not load your profile. Try again.")
        return
      }

      const result = await saveUserReview(
        authUserId,
        {
          rating,
          title,
          review,
          would_recommend: wouldRecommend,
        },
        {
          username: profile.username,
          avatar_url: profile.avatar_url,
        },
        existing
      )

      if (!result.ok) {
        setError(result.message)
        return
      }

      setExisting(result.row)
      setSuccess(true)
      onSaved?.(result.row)
    } finally {
      submittingRef.current = false
      setBusy(false)
    }
  }

  const statusNote = existing
    ? existing.status === "approved"
      ? "Your review is approved and may appear on the homepage when featured."
      : existing.status === "rejected"
        ? "Your review was not approved. You can edit and resubmit for review."
        : "Your review is pending review. Edits will require re-approval."
    : "Your review will be reviewed before it appears on the homepage."

  const reviewLength = review.trim().length

  return (
    <Modal
      open={open}
      onClose={() => {
        if (!busy) onClose()
      }}
      title={existing ? "Edit Your Review" : "Leave a Review"}
      size="lg"
      belowNavbar
      panelClassName="max-h-[calc(100vh-5rem)] overflow-y-auto"
    >
      {loading ? (
        <p className="py-8 text-center text-sm text-gray-400">Loading your review…</p>
      ) : error && !success ? (
        <div className="py-8 text-center">
          <p className="rounded-lg border border-red-500/30 bg-red-500/10 px-3 py-2 text-sm text-red-200">
            {error}
          </p>
        </div>
      ) : success ? (
        <div className="py-8 text-center">
          <p className="text-lg font-semibold text-emerald-300">Thank you!</p>
          <p className="mt-2 text-sm text-gray-300">
            Your review was saved and sent for review.
          </p>
        </div>
      ) : (
        <form onSubmit={(e) => void handleSubmit(e)} className="space-y-4">
          <p className="text-sm text-gray-400">{statusNote}</p>

          <div>
            <span className={submissionLabel}>Overall Rating</span>
            <StarRatingInput value={rating} onChange={setRating} disabled={busy} />
          </div>

          <div>
            <label htmlFor="user-review-title" className={submissionLabel}>
              Title <span className="text-gray-500">(optional)</span>
            </label>
            <input
              id="user-review-title"
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder='Short headline — e.g. "Exactly what I needed"'
              maxLength={120}
              className={submissionInput}
              disabled={busy}
            />
          </div>

          <div>
            <label htmlFor="user-review-body" className={submissionLabel}>
              Review
            </label>
            <textarea
              id="user-review-body"
              value={review}
              onChange={(e) => setReview(e.target.value)}
              placeholder="Tell us honestly what you think about TradeTraxs…"
              rows={6}
              minLength={REVIEW_MIN}
              maxLength={REVIEW_MAX}
              className={submissionTextarea}
              disabled={busy}
              required
            />
            <p className="mt-1 text-xs text-gray-500">
              Recommended length: {REVIEW_MIN}–{REVIEW_MAX} characters ({reviewLength}/{REVIEW_MAX})
            </p>
          </div>

          <label className="flex cursor-pointer items-start gap-3 text-sm text-gray-300">
            <input
              type="checkbox"
              checked={wouldRecommend}
              onChange={(e) => setWouldRecommend(e.target.checked)}
              disabled={busy}
              className="mt-0.5 h-4 w-4 shrink-0 rounded border-white/20 bg-white/10 text-blue-500 focus:ring-2 focus:ring-blue-400 focus:ring-offset-0"
            />
            <span>I would recommend TradeTraxs to another trader.</span>
          </label>

          {error ? (
            <p className="rounded-lg border border-red-500/30 bg-red-500/10 px-3 py-2 text-sm text-red-200">
              {error}
            </p>
          ) : null}

          <button type="submit" disabled={busy} className={submissionSubmitButton}>
            {busy ? "Submitting…" : existing ? "Update Review" : "Submit Review"}
          </button>
        </form>
      )}
    </Modal>
  )
}
