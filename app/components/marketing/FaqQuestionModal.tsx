"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import ModalCloseButton from "@/app/components/ui/ModalCloseButton"
import { resolveContactFormAutofill } from "@/lib/contactFormAutofill"
import {
  FAQ_CONTACT_CATEGORY,
  submitPublicContact,
} from "@/lib/publicContact"
import {
  submissionFormCard,
  submissionInput,
  submissionLabel,
  submissionSubmitButton,
  submissionSubtitle,
  submissionTextarea,
  submissionTitle,
} from "@/lib/submissionFormStyles"
import { useUserProfile } from "@/lib/UserProfileProvider"

type FaqQuestionModalProps = {
  open: boolean
  initialQuestion?: string
  onClose: () => void
  onSuccess: () => void
}

export default function FaqQuestionModal({
  open,
  initialQuestion = "",
  onClose,
  onSuccess,
}: FaqQuestionModalProps) {
  const { user, loading: profileLoading } = useUserProfile()
  const submittingRef = useRef(false)
  const [name, setName] = useState("")
  const [email, setEmail] = useState("")
  const [question, setQuestion] = useState("")
  const [details, setDetails] = useState("")
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const resetForm = useCallback(() => {
    setName("")
    setEmail("")
    setQuestion("")
    setDetails("")
    setError(null)
    setBusy(false)
  }, [])

  useEffect(() => {
    if (!open) {
      resetForm()
      return
    }

    resetForm()
    setQuestion(initialQuestion.trim())

    if (!user?.id) return

    let cancelled = false

    void (async () => {
      if (profileLoading) return
      const autofill = await resolveContactFormAutofill(user.id, user.email)
      if (cancelled) return
      if (autofill.name) setName(autofill.name)
      if (autofill.email) setEmail(autofill.email)
    })()

    return () => {
      cancelled = true
    }
  }, [open, initialQuestion, user, profileLoading, resetForm])

  useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape" && !busy) onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, busy, onClose])

  if (!open) return null

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (submittingRef.current || busy) return

    const trimmedQuestion = question.trim()
    if (!trimmedQuestion) {
      setError("Question is required")
      return
    }

    submittingRef.current = true
    setBusy(true)
    setError(null)

    try {
      const detailsTrimmed = details.trim()
      const message = detailsTrimmed
        ? `Question:\n${trimmedQuestion}\n\nOptional details:\n${detailsTrimmed}`
        : `Question:\n${trimmedQuestion}`

      const result = await submitPublicContact({
        category: FAQ_CONTACT_CATEGORY.category,
        name: name.trim(),
        email: email.trim(),
        subject: FAQ_CONTACT_CATEGORY.subject,
        message,
      })

      if (!result.ok) {
        setError(result.message)
        setBusy(false)
        return
      }

      resetForm()
      onSuccess()
      onClose()
    } finally {
      submittingRef.current = false
    }
  }

  return (
    <div
      className="fixed inset-0 z-[10050] flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm"
      onClick={() => {
        if (!busy) onClose()
      }}
    >
      <div
        className={`max-h-[90vh] w-full max-w-lg overflow-y-auto ${submissionFormCard}`}
        role="dialog"
        aria-modal="true"
        aria-labelledby="faq-question-title"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-start justify-between gap-3">
          <div className="min-w-0 flex-1">
            <h2 id="faq-question-title" className={submissionTitle}>
              Send a Question
            </h2>
            <p className={`${submissionSubtitle} mb-0 mt-2 text-left`}>
              {FAQ_CONTACT_CATEGORY.description}
            </p>
          </div>
          <ModalCloseButton onClick={onClose} disabled={busy} />
        </div>

        <form className="space-y-1" onSubmit={(e) => void handleSubmit(e)}>
          <label className={submissionLabel} htmlFor="faq-q-name">
            Name
          </label>
          <input
            id="faq-q-name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            required
            maxLength={200}
            disabled={busy}
            className={submissionInput}
            placeholder="Your name"
            autoComplete="name"
          />

          <label className={submissionLabel} htmlFor="faq-q-email">
            Email
          </label>
          <input
            id="faq-q-email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            maxLength={320}
            disabled={busy}
            className={submissionInput}
            placeholder="you@example.com"
            autoComplete="email"
          />

          <label className={submissionLabel} htmlFor="faq-q-question">
            Question
          </label>
          <textarea
            id="faq-q-question"
            value={question}
            onChange={(e) => setQuestion(e.target.value)}
            required
            rows={3}
            disabled={busy}
            className={submissionTextarea}
            placeholder="What would you like to know?"
          />

          <label className={submissionLabel} htmlFor="faq-q-details">
            Optional Details
          </label>
          <textarea
            id="faq-q-details"
            value={details}
            onChange={(e) => setDetails(e.target.value)}
            rows={3}
            disabled={busy}
            className={submissionTextarea}
            placeholder="Any extra context that might help"
          />

          {error ? (
            <p className="mb-3 rounded-lg border border-red-400/30 bg-red-500/10 px-3 py-2 text-sm text-red-200">
              {error}
            </p>
          ) : null}

          <div className="flex flex-col-reverse gap-2 pt-1 sm:flex-row sm:justify-end">
            <button
              type="button"
              onClick={onClose}
              disabled={busy}
              className="rounded-xl border border-white/15 bg-white/5 px-4 py-2.5 text-sm font-medium text-gray-200 transition hover:bg-white/10 disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={
                busy || !name.trim() || !email.trim() || !question.trim()
              }
              className={`${submissionSubmitButton} sm:w-auto sm:min-w-[10rem] sm:px-6`}
            >
              {busy ? "Sending…" : "Send Question"}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
