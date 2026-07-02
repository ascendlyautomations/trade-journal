"use client"

import {
  LANDING_CARD_FULL,
  LANDING_HEADLINE_SM,
  LANDING_LEAD,
  LANDING_SECTION_BORDER,
  LANDING_SECTION_SHELL,
  LANDING_SECTION_SPACING,
} from "@/lib/landingPageUi"

export type TestimonialSlot = {
  id: string
  quote: string | null
  name: string | null
  role: string | null
}

export const LANDING_TESTIMONIAL_SLOTS: TestimonialSlot[] = [
  { id: "slot-1", quote: null, name: null, role: null },
  { id: "slot-2", quote: null, name: null, role: null },
  { id: "slot-3", quote: null, name: null, role: null },
]

function TestimonialCard({ slot }: { slot: TestimonialSlot }) {
  const hasContent = Boolean(slot.quote && slot.name)

  return (
    <article className={`${LANDING_CARD_FULL} flex min-h-[220px] flex-col p-8`}>
      {hasContent ? (
        <>
          <p className="flex-1 text-base leading-relaxed text-gray-300">
            &ldquo;{slot.quote}&rdquo;
          </p>
          <footer className="mt-6 border-t border-white/10 pt-4">
            <p className="font-medium text-white">{slot.name}</p>
            {slot.role ? <p className="mt-1 text-sm text-gray-500">{slot.role}</p> : null}
          </footer>
        </>
      ) : (
        <div className="flex flex-1 flex-col items-center justify-center text-center">
          <p className="text-sm font-medium text-gray-500">Beta testimonial</p>
          <p className="mt-2 max-w-[200px] text-xs leading-relaxed text-gray-600">
            Real trader feedback will appear here after launch.
          </p>
        </div>
      )}
    </article>
  )
}

export default function LandingTestimonialsSection() {
  return (
    <section
      id="testimonials"
      className={`relative z-10 ${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}
      aria-labelledby="testimonials-heading"
    >
      <div className={LANDING_SECTION_SHELL}>
        <div className="mx-auto max-w-3xl text-center">
          <h2 id="testimonials-heading" className={LANDING_HEADLINE_SM}>
            Traders are making it home.
          </h2>
          <p className={`${LANDING_LEAD} mx-auto mt-5`}>
            Real stories from the community — coming soon.
          </p>
        </div>

        <div className="mt-14 grid gap-5 md:grid-cols-3">
          {LANDING_TESTIMONIAL_SLOTS.map((slot) => (
            <TestimonialCard key={slot.id} slot={slot} />
          ))}
        </div>
      </div>
    </section>
  )
}
