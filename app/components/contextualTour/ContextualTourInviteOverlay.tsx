"use client"

import { useEffect, useState } from "react"
import { createPortal } from "react-dom"
import { useContextualTour } from "@/lib/contextualTour/ContextualTourProvider"
import "./contextualTour.css"

export default function ContextualTourInviteOverlay() {
  const tour = useContextualTour()
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!tour.showInvite) return
    const prev = document.body.style.overflow
    document.body.style.overflow = "hidden"
    return () => {
      document.body.style.overflow = prev
    }
  }, [tour.showInvite])

  if (!mounted || !tour.showInvite) return null

  return createPortal(
    <div
      className="tt-contextual-tour-root tt-contextual-tour-overlay flex items-end justify-center bg-[var(--tt-tour-scrim)] p-4 pb-[max(1rem,env(safe-area-inset-bottom))] sm:items-center sm:p-6"
      role="dialog"
      aria-modal="true"
      aria-labelledby="tt-contextual-tour-invite-title"
      aria-describedby="tt-contextual-tour-invite-body"
    >
      <div className="tt-contextual-tour-card w-full max-w-lg rounded-2xl p-5 shadow-2xl sm:p-6">
        <p className="tt-contextual-tour-card-muted mb-1 text-xs font-medium uppercase tracking-wide">
          Welcome to TradeTraxs
        </p>
        <h2
          id="tt-contextual-tour-invite-title"
          className="text-lg font-semibold leading-snug"
        >
          Take a quick app walkthrough?
        </h2>
        <p
          id="tt-contextual-tour-invite-body"
          className="tt-contextual-tour-card-muted mt-2 text-sm leading-relaxed"
        >
          We&apos;ll show you Dashboard, Feed, Profile, broker connections, and
          settings in about a minute. You can replay it anytime from Settings.
        </p>
        <div className="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:items-center sm:justify-end">
          <button
            type="button"
            className="rounded-xl px-4 py-2.5 text-sm font-medium tt-contextual-tour-card-muted transition hover:text-[var(--tt-tour-card-text)]"
            onClick={tour.declineInvite}
          >
            Skip tour
          </button>
          <button
            type="button"
            className="rounded-xl bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-500 sm:min-w-[8.5rem]"
            onClick={tour.acceptInvite}
          >
            Start tour
          </button>
        </div>
      </div>
    </div>,
    document.body
  )
}
