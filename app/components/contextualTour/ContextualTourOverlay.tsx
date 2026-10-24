"use client"

import { useEffect, useMemo, useState } from "react"
import { createPortal } from "react-dom"
import { useContextualTour } from "@/lib/contextualTour/ContextualTourProvider"
import {
  computeTourHighlightRect,
  computeTourPopoverPlacement,
} from "@/lib/contextualTour/popoverLayout"
import { stepRole } from "@/lib/contextualTour/types"
import ContextualTourHighlightRing from "./ContextualTourHighlightRing"
import "./contextualTour.css"

function TourStepCard({
  step,
  tour,
  isSectionContinue,
  isFinish,
  primaryLabel,
}: {
  step: NonNullable<ReturnType<typeof useContextualTour>["visibleStep"]>
  tour: ReturnType<typeof useContextualTour>
  isSectionContinue: boolean
  isFinish: boolean
  primaryLabel: string
}) {
  return (
    <div data-tt-contextual-tour-card className="rounded-2xl p-4 sm:p-5">
      {!isSectionContinue ? (
        <p data-tt-tour-muted className="mb-1 text-xs font-medium uppercase tracking-wide">
          {tour.progressLabel}
        </p>
      ) : null}
      <h2 data-tt-tour-title id="tt-contextual-tour-title" className="text-base font-semibold leading-snug sm:text-lg">
        {step.title}
      </h2>
      {step.message ? (
        <p data-tt-tour-body id="tt-contextual-tour-body" className="mt-1.5 text-sm leading-relaxed">
          {step.message}
        </p>
      ) : null}

      <div className="mt-4 flex flex-wrap items-center gap-2">
        {!isSectionContinue && !isFinish && tour.stepIndex > 0 ? (
          <button
            type="button"
            data-tt-tour-secondary
            className="rounded-xl border px-3 py-1.5 text-sm font-medium transition hover:bg-white/10"
            onClick={tour.back}
          >
            Back
          </button>
        ) : null}
        <button
          type="button"
          className="ml-auto rounded-xl bg-blue-600 px-3 py-1.5 text-sm font-semibold text-white transition hover:bg-blue-500"
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
            data-tt-tour-secondary
            className="rounded-xl px-2 py-1.5 text-sm font-medium transition hover:text-white"
            onClick={tour.skip}
          >
            Skip
          </button>
        ) : null}
      </div>
    </div>
  )
}

export default function ContextualTourOverlay() {
  const tour = useContextualTour()
  const [mounted, setMounted] = useState(false)
  const [viewport, setViewport] = useState({ width: 0, height: 0 })

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!tour.showsOverlay) return
    const sync = () => {
      setViewport({ width: window.innerWidth, height: window.innerHeight })
    }
    sync()
    window.addEventListener("resize", sync)
    window.addEventListener("scroll", sync, true)
    return () => {
      window.removeEventListener("resize", sync)
      window.removeEventListener("scroll", sync, true)
    }
  }, [tour.showsOverlay])

  const step = tour.visibleStep
  const role = step ? stepRole(step) : null

  const highlightRect = useMemo(
    () => computeTourHighlightRect(tour.spotlightRect),
    [tour.spotlightRect]
  )

  const popover = useMemo(() => {
    if (viewport.width <= 0) return null
    return computeTourPopoverPlacement(tour.spotlightRect, viewport)
  }, [tour.spotlightRect, viewport])

  if (!mounted || !tour.showsOverlay || !step || !popover) return null

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

  return createPortal(
    <>
      <ContextualTourHighlightRing rect={highlightRect} />
      {showCard ? (
        <div
          data-tt-contextual-tour-popover
          role="region"
          aria-label="App walkthrough step"
          aria-labelledby="tt-contextual-tour-title"
          aria-describedby={step.message ? "tt-contextual-tour-body" : undefined}
          className="pointer-events-auto fixed z-[10075] transition-[top,left] duration-200 ease-out motion-reduce:transition-none"
          style={{
            top: popover.top,
            left: popover.left,
            width: popover.width,
          }}
        >
          <TourStepCard
            step={step}
            tour={tour}
            isSectionContinue={isSectionContinue}
            isFinish={isFinish}
            primaryLabel={primaryLabel}
          />
        </div>
      ) : null}
    </>,
    document.body
  )
}
