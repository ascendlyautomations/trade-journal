"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { resolveContactFormAutofill } from "@/lib/contactFormAutofill"
import {
  PUBLIC_CONTACT_CATEGORY_LABELS,
  submitPublicContact,
  type PublicContactCategoryConfig,
} from "@/lib/publicContact"
import { useUserProfile } from "@/lib/UserProfileProvider"
import {
  submissionFormCard,
  submissionInput,
  submissionLabel,
  submissionSubmitButton,
  submissionSubtitle,
  submissionTextarea,
  submissionTitle,
} from "@/lib/submissionFormStyles"

const SUCCESS_AUTO_CLOSE_MS = 2500

const SUCCESS_MESSAGE =
  "✓ Your message has been sent successfully.\n\nOur team will get back to you as soon as possible."

type ContactFormModalProps = {
  open: boolean
  category: PublicContactCategoryConfig | null
  onClose: () => void
}

export default function ContactFormModal({
  open,
  category,
  onClose,
}: ContactFormModalProps) {
  const { user, loading: profileLoading } = useUserProfile()
  const submittingRef = useRef(false)
  const [name, setName] = useState("")
  const [email, setEmail] = useState("")
  const [message, setMessage] = useState("")
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState(false)

  const resetForm = useCallback(() => {
    setName("")
    setEmail("")
    setMessage("")
    setError(null)
    setSuccess(false)
    setBusy(false)
  }, [])

  useEffect(() => {
    if (!open || !category) {
      resetForm()
      return
    }

    resetForm()

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
  }, [open, category, user, profileLoading, resetForm])

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

  if (!open || !category) return null

  const modalTitle = PUBLIC_CONTACT_CATEGORY_LABELS[category.category]

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (submittingRef.current || busy || success) return

    submittingRef.current = true
    setBusy(true)
    setError(null)

    try {
      const result = await submitPublicContact({
        category: category!.category,
        name: name.trim(),
        email: email.trim(),
        subject: category!.subject,
        message: message.trim(),
      })

      if (!result.ok) {
        setError(result.message)
        setBusy(false)
        return
      }

      setSuccess(true)
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
        className={`max-h-[90vh] w-full max-w-lg overflow-y-auto ${submissionFormCard}`}
        role="dialog"
        aria-modal="true"
        aria-labelledby="contact-form-title"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-start justify-between gap-3">
          <div className="min-w-0 flex-1">
            <h2 id="contact-form-title" className={submissionTitle}>
              {modalTitle}
            </h2>
            <p className={`${submissionSubtitle} mb-0 mt-2 text-left`}>
              {category.description}
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            disabled={busy || success}
            className="shrink-0 rounded px-2 py-1 text-gray-400 hover:bg-white/10 hover:text-white disabled:opacity-50"
            aria-label="Close"
          >
            ✕
          </button>
        </div>

        {success ? (
          <p className="whitespace-pre-line rounded-lg border border-emerald-400/30 bg-emerald-500/10 px-4 py-3 text-sm text-emerald-200">
            {SUCCESS_MESSAGE}
          </p>
        ) : (
          <form className="space-y-1" onSubmit={(e) => void handleSubmit(e)}>
            <label className={submissionLabel} htmlFor="contact-name">
              Name
            </label>
            <input
              id="contact-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              required
              maxLength={200}
              disabled={busy}
              className={submissionInput}
              placeholder="Your name"
              autoComplete="name"
            />

            <label className={submissionLabel} htmlFor="contact-email">
              Email
            </label>
            <input
              id="contact-email"
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

            <label className={submissionLabel} htmlFor="contact-subject">
              Subject
            </label>
            <input
              id="contact-subject"
              value={category.subject}
              readOnly
              disabled={busy}
              className={`${submissionInput} cursor-default opacity-90`}
              aria-readonly="true"
            />

            <label className={submissionLabel} htmlFor="contact-message">
              Message
            </label>
            <textarea
              id="contact-message"
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              required
              rows={5}
              disabled={busy}
              className={submissionTextarea}
              placeholder="How can we help?"
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
                disabled={busy || success}
                className="rounded-xl border border-white/15 bg-white/5 px-4 py-2.5 text-sm font-medium text-gray-200 transition hover:bg-white/10 disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={
                  busy ||
                  success ||
                  !name.trim() ||
                  !email.trim() ||
                  !message.trim()
                }
                className={`${submissionSubmitButton} sm:w-auto sm:min-w-[10rem] sm:px-6`}
              >
                {busy && !success ? "Submitting…" : "Submit"}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  )
}
