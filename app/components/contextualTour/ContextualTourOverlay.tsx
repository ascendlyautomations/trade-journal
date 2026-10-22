"use client"

import { useEffect, useMemo, useState } from "react"
import { createPortal } from "react-dom"
import { useContextualTour } from "@/lib/contextualTour/ContextualTourProvider"
import { stepRole } from "@/lib/contextualTour/types"
import "./contextualTour.css"

const SPOTLIGHT_PAD = 8
const SPOTLIGHT_RADIUS = 12

export default function ContextualTourOverlay() {
  const tour = useContextualTour()
  const [mounted, setMounted] = useState(false)
  const [reduceMotion, setReduceMotion] = useState(false)

  useEffect(() => {
    setMounted(true)
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)")
    const sync = () => setReduceMotion(mq.matches)
    sync()
    mq.addEventListener("change", sync)
    return () => mq.removeEventListener("change", sync)
  }, [])

  useEffect(() => {
    if (!tour.showsOverlay) return
    const prev = document.body.style.overflow
    document.body.style.overflow = "hidden"
    return () => {
      document.body.style.overflow = prev
    }
  }, [tour.showsOverlay])

  const step = tour.visibleStep
  const role = step ? stepRole(step) : null

  const hole = useMemo(() => {
    const r = tour.spotlightRect
    if (!r) return null
    return {
      x: Math.max(0, r.x - SPOTLIGHT_PAD),
      y: Math.max(0, r.y - SPOTLIGHT_PAD),
      w: r.width + SPOTLIGHT_PAD * 2,
      h: r.height + SPOTLIGHT_PAD * 2,
    }
  }, [tour.spotlightRect])

  if (!mounted || !tour.showsOverlay || !step) return null

  const isSectionContinue = role === "sectionContinue"
  const isFinish = role === "finish"
  const showCard =
    tour.showsExplanationCard || isSectionContinue || isFinish

  const primaryLabel = isFinish
    ? "Got it"
    : isSectionContinue
      ? step.title.includes("Feed")
        ? "Continue to Feed"
        : step.title.includes("Profile")
          ? "Continue to Profile"
          : "Continue"
      : "Next"

  const content = (
    <div
      className="tt-contextual-tour-root tt-contextual-tour-overlay"
      role="dialog"
      aria-modal="true"
      aria-labelledby="tt-contextual-tour-title"
      aria-describedby="tt-contextual-tour-body"
    >
      <svg
        className="absolute inset-0 h-full w-full"
        aria-hidden
        style={{ pointerEvents: "auto" }}
      >
        <defs>
          <mask id="tt-tour-spotlight-mask">
            <rect width="100%" height="100%" fill="white" />
            {hole ? (
              <rect
                x={hole.x}
                y={hole.y}
                width={hole.w}
                height={hole.h}
                rx={SPOTLIGHT_RADIUS}
                ry={SPOTLIGHT_RADIUS}
                fill="black"
                style={{
                  transition: reduceMotion
                    ? "none"
                    : "x 220ms ease, y 220ms ease, width 220ms ease, height 220ms ease",
                }}
              />
            ) : null}
          </mask>
        </defs>
        <rect
          width="100%"
          height="100%"
          fill="var(--tt-tour-scrim)"
          mask="url(#tt-tour-spotlight-mask)"
          onClick={(e) => e.stopPropagation()}
        />
      </svg>

      {showCard ? (
        <div className="pointer-events-none absolute inset-x-0 bottom-0 flex justify-center p-4 pb-[max(1rem,env(safe-area-inset-bottom))] sm:p-6">
          <div className="tt-contextual-tour-card pointer-events-auto w-full max-w-lg rounded-2xl p-5 shadow-2xl sm:p-6">
            {!isSectionContinue ? (
              <p className="tt-contextual-tour-card-muted mb-1 text-xs font-medium uppercase tracking-wide">
                {tour.progressLabel}
              </p>
            ) : null}
            <h2
              id="tt-contextual-tour-title"
              className="text-lg font-semibold leading-snug"
            >
              {step.title}
            </h2>
            {step.message ? (
              <p
                id="tt-contextual-tour-body"
                className="tt-contextual-tour-card-muted mt-2 text-sm leading-relaxed"
              >
                {step.message}
              </p>
            ) : null}

            <div className="mt-5 flex flex-wrap items-center gap-2">
              {!isSectionContinue && !isFinish && tour.stepIndex > 0 ? (
                <button
                  type="button"
                  className="rounded-xl border border-white/15 px-4 py-2 text-sm font-medium transition hover:bg-white/10"
                  onClick={tour.back}
                >
                  Back
                </button>
              ) : null}
              <button
                type="button"
                className="ml-auto rounded-xl bg-blue-600 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-500"
                onClick={() => {
                  if (isFinish) tour.finish()
                  else tour.next()
                }}
              >
                {primaryLabel}
              </button>
              {!isFinish ? (
                <button
                  type="button"
                  className="rounded-xl px-3 py-2 text-sm font-medium tt-contextual-tour-card-muted transition hover:text-[var(--tt-tour-card-text)]"
                  onClick={tour.skip}
                >
                  Skip
                </button>
              ) : null}
            </div>
          </div>
        </div>
      ) : null}
    </div>
  )

  return createPortal(content, document.body)
}
