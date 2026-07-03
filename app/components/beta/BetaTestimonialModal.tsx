"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import Modal from "@/app/components/ui/Modal"
import StarRatingInput from "@/app/components/beta/StarRatingInput"
import { supabase } from "@/lib/supabaseClient"
import {
  fetchMyBetaTestimonial,
  saveBetaTestimonial,
  type BetaTestimonialRow,
} from "@/lib/betaTestimonials"
import {
  submissionInput,
  submissionLabel,
  submissionSubmitButton,
  submissionTextarea,
} from "@/lib/submissionFormStyles"

type BetaTestimonialModalProps = {
  open: boolean
  userId: string | null
  onClose: () => void
  onSaved?: (row: BetaTestimonialRow) => void
}

export default function BetaTestimonialModal({
  open,
  userId,
  onClose,
  onSaved,
}: BetaTestimonialModalProps) {
  const router = useRouter()
  const submittingRef = useRef(false)
  const [loading, setLoading] = useState(false)
  const [existing, setExisting] = useState<BetaTestimonialRow | null>(null)
  const [rating, setRating] = useState(5)
  const [title, setTitle] = useState("")
  const [review, setReview] = useState("")
  const [pros, setPros] = useState("")
  const [cons, setCons] = useState("")
  const [wouldRecommend, setWouldRecommend] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState(false)

  const resetForm = useCallback(() => {
    setRating(5)
    setTitle("")
    setReview("")
    setPros("")
    setCons("")
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
      const row = await fetchMyBetaTestimonial(userId)
      if (cancelled) return

      if (row) {
        setExisting(row)
        setRating(row.rating)
        setTitle(row.title)
        setReview(row.review)
        setPros(row.pros ?? "")
        setCons(row.cons ?? "")
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
      const {
        data: { user },
        error: authError,
      } = await supabase.auth.getUser()

      if (authError || !user) {
        onClose()
        router.push("/login")
        return
      }

      const result = await saveBetaTestimonial(
        user.id,
        {
          rating,
          title,
          review,
          pros,
          cons,
          would_recommend: wouldRecommend,
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
    ? existing.approved
      ? "Your testimonial is approved and may appear on the homepage."
      : "Your testimonial is pending review. Edits to your review will require re-approval."
    : "Your testimonial will be reviewed before it appears on the homepage."

  return (
    <Modal
      open={open}
      onClose={() => {
        if (!busy) onClose()
      }}
      title={existing ? "Edit Beta Feedback" : "Leave Beta Feedback"}
      size="lg"
      belowNavbar
      panelClassName="max-h-[calc(100vh-5rem)] overflow-y-auto"
    >
      {loading ? (
        <p className="py-8 text-center text-sm text-gray-400">Loading your feedback…</p>
      ) : success ? (
        <div className="py-8 text-center">
          <p className="text-lg font-semibold text-emerald-300">Thank you!</p>
          <p className="mt-2 text-sm text-gray-300">
            Your beta feedback was saved{existing?.approved ? "" : " and sent for review"}.
          </p>
        </div>
      ) : (
        <form onSubmit={(e) => void handleSubmit(e)} className="space-y-4">
          <p className="text-sm text-gray-400">{statusNote}</p>

          <div>
            <span className={submissionLabel}>Rating</span>
            <StarRatingInput value={rating} onChange={setRating} disabled={busy} />
          </div>

          <div>
            <label htmlFor="beta-testimonial-title" className={submissionLabel}>
              Title
            </label>
            <input
              id="beta-testimonial-title"
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder='e.g. "Incredible analytics"'
              maxLength={120}
              className={submissionInput}
              disabled={busy}
              required
            />
          </div>

          <div>
            <label htmlFor="beta-testimonial-review" className={submissionLabel}>
              Review
            </label>
            <textarea
              id="beta-testimonial-review"
              value={review}
              onChange={(e) => setReview(e.target.value)}
              placeholder="Share your experience with TradeTraxs during beta…"
              rows={5}
              className={submissionTextarea}
              disabled={busy}
              required
            />
          </div>

          <div>
            <label htmlFor="beta-testimonial-pros" className={submissionLabel}>
              Pros
            </label>
            <textarea
              id="beta-testimonial-pros"
              value={pros}
              onChange={(e) => setPros(e.target.value)}
              placeholder="What did you like most?"
              rows={3}
              className={submissionTextarea}
              disabled={busy}
            />
          </div>

          <div>
            <label htmlFor="beta-testimonial-cons" className={submissionLabel}>
              Cons
            </label>
            <textarea
              id="beta-testimonial-cons"
              value={cons}
              onChange={(e) => setCons(e.target.value)}
              placeholder="What needs improvement?"
              rows={3}
              className={submissionTextarea}
              disabled={busy}
            />
          </div>

          <fieldset>
            <legend className={submissionLabel}>Would you recommend TradeTraxs?</legend>
            <div className="flex gap-3">
              <button
                type="button"
                onClick={() => setWouldRecommend(true)}
                disabled={busy}
                className={`rounded-lg border px-4 py-2 text-sm font-medium transition ${
                  wouldRecommend
                    ? "border-emerald-400/50 bg-emerald-500/20 text-emerald-100"
                    : "border-white/15 bg-white/5 text-gray-300 hover:bg-white/10"
                }`}
              >
                Yes
              </button>
              <button
                type="button"
                onClick={() => setWouldRecommend(false)}
                disabled={busy}
                className={`rounded-lg border px-4 py-2 text-sm font-medium transition ${
                  !wouldRecommend
                    ? "border-red-400/40 bg-red-500/15 text-red-100"
                    : "border-white/15 bg-white/5 text-gray-300 hover:bg-white/10"
                }`}
              >
                No
              </button>
            </div>
          </fieldset>

          {error ? (
            <p className="rounded-lg border border-red-500/30 bg-red-500/10 px-3 py-2 text-sm text-red-200">
              {error}
            </p>
          ) : null}

          <button type="submit" disabled={busy} className={submissionSubmitButton}>
            {busy ? "Saving…" : existing ? "Update Feedback" : "Submit Feedback"}
          </button>
        </form>
      )}
    </Modal>
  )
}
