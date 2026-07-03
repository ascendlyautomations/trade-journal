"use client"

import { useEffect, useMemo, useState } from "react"
import { SafeProfileAvatar } from "@/app/components/SafeProfileAvatar"
import StarRatingDisplay from "@/app/components/beta/StarRatingDisplay"
import {
  computeBetaTestimonialStats,
  fetchPublicBetaTestimonials,
  formatTradingExperienceLabel,
  selectHomepageTestimonials,
  type PublicBetaTestimonial,
} from "@/lib/betaTestimonials"
import {
  LANDING_CARD_FULL,
  LANDING_HEADLINE_SM,
  LANDING_LEAD,
  LANDING_SECTION_BORDER,
  LANDING_SECTION_SHELL,
  LANDING_SECTION_SPACING,
} from "@/lib/landingPageUi"

function TestimonialCard({ testimonial }: { testimonial: PublicBetaTestimonial }) {
  const username = testimonial.username?.trim() || "Beta Tester"
  const experience = formatTradingExperienceLabel(testimonial)

  return (
    <article className={`${LANDING_CARD_FULL} flex min-h-[280px] flex-col p-6 md:p-8`}>
      <div className="flex items-start justify-between gap-3">
        <StarRatingDisplay rating={testimonial.rating} className="text-base md:text-lg" />
        <span className="shrink-0 rounded-full border border-amber-400/30 bg-amber-500/15 px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wide text-amber-200">
          Verified Beta Tester
        </span>
      </div>

      <h3 className="mt-4 text-lg font-semibold text-white">{testimonial.title}</h3>
      <p className="mt-3 flex-1 text-base leading-relaxed text-gray-300">
        &ldquo;{testimonial.review}&rdquo;
      </p>

      <footer className="mt-6 flex items-center gap-3 border-t border-white/10 pt-4">
        <SafeProfileAvatar
          src={testimonial.avatar_url}
          alt={username}
          className="h-10 w-10 shrink-0"
        />
        <div className="min-w-0">
          <p className="truncate font-medium text-white">{username}</p>
          {experience ? (
            <p className="mt-0.5 truncate text-sm text-gray-500">{experience}</p>
          ) : null}
        </div>
      </footer>
    </article>
  )
}

function TestimonialPlaceholder({ index }: { index: number }) {
  return (
    <article className={`${LANDING_CARD_FULL} flex min-h-[280px] flex-col p-8`}>
      <div className="flex flex-1 flex-col items-center justify-center text-center">
        <p className="text-sm font-medium text-gray-500">Beta testimonial {index}</p>
        <p className="mt-2 max-w-[220px] text-xs leading-relaxed text-gray-600">
          Beta feedback will appear here as testers share their experience.
        </p>
      </div>
    </article>
  )
}

export default function LandingTestimonialsSection() {
  const [testimonials, setTestimonials] = useState<PublicBetaTestimonial[]>([])
  const [loaded, setLoaded] = useState(false)

  useEffect(() => {
    let cancelled = false
    void (async () => {
      const rows = await fetchPublicBetaTestimonials()
      if (!cancelled) {
        setTestimonials(rows)
        setLoaded(true)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [])

  const stats = useMemo(
    () => computeBetaTestimonialStats(testimonials),
    [testimonials]
  )

  const featuredCards = useMemo(
    () => selectHomepageTestimonials(testimonials, 3),
    [testimonials]
  )

  const displayCards =
    featuredCards.length > 0
      ? featuredCards
      : loaded
        ? []
        : [null, null, null]

  return (
    <section
      id="testimonials"
      className={`relative z-10 ${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}
      aria-labelledby="testimonials-heading"
    >
      <div className={LANDING_SECTION_SHELL}>
        <div className="mx-auto max-w-3xl text-center">
          <h2 id="testimonials-heading" className={LANDING_HEADLINE_SM}>
            Real Stories From The Community
          </h2>
          <p className={`${LANDING_LEAD} mx-auto mt-5`}>
            Traders are making TradeTraxs home.
          </p>

          {stats.count > 0 ? (
            <div className="mt-8 flex flex-col items-center gap-2">
              <div className="flex flex-wrap items-center justify-center gap-3">
                <StarRatingDisplay
                  rating={Math.round(stats.averageRating)}
                  className="text-xl"
                />
                <span className="text-lg font-semibold text-white tabular-nums">
                  {stats.averageRating.toFixed(1)}/5
                </span>
              </div>
              <p className="text-sm text-gray-500">
                Based on {stats.count} Beta Tester{stats.count === 1 ? "" : "s"}
              </p>
            </div>
          ) : loaded ? (
            <p className="mt-6 text-sm text-gray-500">
              Beta testimonials will appear here as they are approved.
            </p>
          ) : null}
        </div>

        <div className="mt-14 grid gap-5 md:grid-cols-3">
          {displayCards.length > 0 ? (
            displayCards.map((testimonial, index) =>
              testimonial ? (
                <TestimonialCard key={testimonial.id} testimonial={testimonial} />
              ) : (
                <TestimonialPlaceholder key={`placeholder-${index}`} index={index + 1} />
              )
            )
          ) : (
            <div className="md:col-span-3">
              <div className={`${LANDING_CARD_FULL} px-6 py-10 text-center`}>
                <p className="text-sm text-gray-500">
                  Beta testimonials will appear here soon.
                </p>
              </div>
            </div>
          )}
        </div>
      </div>
    </section>
  )
}
