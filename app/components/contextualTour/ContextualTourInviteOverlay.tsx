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

  if (!mounted || !tour.showInvite) return null

  return createPortal(
    <div
      data-tt-contextual-tour-popover
      role="region"
      aria-label="App walkthrough invitation"
      aria-labelledby="tt-contextual-tour-invite-title"
      aria-describedby="tt-contextual-tour-invite-body"
      className="pointer-events-auto fixed bottom-[max(1rem,env(safe-area-inset-bottom))] left-1/2 z-[10075] w-[min(100%-2rem,32rem)] -translate-x-1/2 sm:bottom-auto sm:top-1/2 sm:-translate-y-1/2"
    >
      <div data-tt-contextual-tour-card className="rounded-2xl p-5 sm:p-6">
        <p data-tt-tour-muted className="mb-1 text-xs font-medium uppercase tracking-wide">
          Welcome to TradeTraxs
        </p>
        <h2
          id="tt-contextual-tour-invite-title"
          data-tt-tour-title
          className="text-lg font-semibold leading-snug"
        >
          Take a quick app walkthrough?
        </h2>
        <p
          id="tt-contextual-tour-invite-body"
          data-tt-tour-body
          className="mt-2 text-sm leading-relaxed"
        >
          We&apos;ll show you Dashboard, Feed, Profile, broker connections, and
          settings in about a minute. You can replay it anytime from Settings.
        </p>
        <div className="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:items-center sm:justify-end">
          <button
            type="button"
            data-tt-tour-secondary
            className="rounded-xl px-4 py-2.5 text-sm font-medium transition hover:text-white"
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
