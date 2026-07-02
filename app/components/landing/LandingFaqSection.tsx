"use client"

import { useState } from "react"
import Link from "next/link"
import { LANDING_FAQ_ITEMS } from "@/lib/landingFaq"
import {
  LANDING_CARD_FULL,
  LANDING_HEADLINE_SM,
  LANDING_SECTION_BORDER,
  LANDING_SECTION_SHELL,
  LANDING_SECTION_SPACING,
} from "@/lib/landingPageUi"

export default function LandingFaqSection() {
  const [openIndex, setOpenIndex] = useState<number | null>(0)

  return (
    <section
      id="faq"
      className={`relative z-10 ${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}
      aria-labelledby="faq-heading"
    >
      <div className={LANDING_SECTION_SHELL}>
        <div className="mx-auto max-w-3xl text-center">
          <h2 id="faq-heading" className={LANDING_HEADLINE_SM}>
            Questions, answered.
          </h2>
        </div>

        <div className="mx-auto mt-12 max-w-2xl space-y-3">
          {LANDING_FAQ_ITEMS.map((item, i) => {
            const isOpen = openIndex === i
            return (
              <div key={item.q} className={`overflow-hidden ${LANDING_CARD_FULL}`}>
                <button
                  type="button"
                  onClick={() => setOpenIndex(isOpen ? null : i)}
                  className="flex w-full items-center justify-between gap-4 px-5 py-4 text-left text-sm font-medium text-white transition hover:bg-white/[0.03] md:px-6 md:py-5 md:text-base"
                  aria-expanded={isOpen}
                >
                  <span>{item.q}</span>
                  <span className="shrink-0 text-gray-500" aria-hidden>
                    {isOpen ? "−" : "+"}
                  </span>
                </button>
                {isOpen ? (
                  <div className="border-t border-white/10 px-5 py-4 text-sm leading-relaxed text-gray-400 md:px-6 md:py-5">
                    {item.a}
                  </div>
                ) : null}
              </div>
            )
          })}
        </div>

        <p className="mt-8 text-center text-sm text-gray-500">
          <Link href="/faq" className="text-emerald-400 transition hover:text-emerald-300">
            View full FAQ →
          </Link>
        </p>
      </div>
    </section>
  )
}
