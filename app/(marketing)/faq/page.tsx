"use client"

import { useState } from "react"
import { TRADETRAXS_FAQ_ITEMS } from "@/lib/faqContent"
import { COMPANY_PAGE_TOP } from "@/lib/companyPageUi"

const faqs = TRADETRAXS_FAQ_ITEMS.map((item) => ({
  q: item.question,
  a: item.answer,
}))

export default function FAQPage() {
  const [openIndex, setOpenIndex] = useState<number | null>(null)

  return (
    <>
      <div
        className={`min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-6 pb-12 text-white ${COMPANY_PAGE_TOP}`}
      >
        <h1 className="mb-2 text-center text-3xl font-bold text-blue-300">
          FAQ
        </h1>
        <p className="mb-10 text-center text-sm text-gray-400">
          Quick answers about TradeTraxs
        </p>

        <div className="mx-auto max-w-2xl space-y-3">
          {faqs.map((item, i) => {
            const isOpen = openIndex === i
            return (
              <div
                key={i}
                className="rounded-xl border border-white/10 bg-[#1e293b]/90 p-4 shadow-lg shadow-black/20 transition-colors hover:border-white/15"
              >
                <button
                  type="button"
                  className="flex w-full cursor-pointer items-center justify-between gap-4 text-left"
                  onClick={() => setOpenIndex(isOpen ? null : i)}
                  aria-expanded={isOpen}
                >
                  <span className="font-medium text-white">{item.q}</span>
                  <span
                    className="shrink-0 tabular-nums text-lg text-emerald-400/90"
                    aria-hidden
                  >
                    {isOpen ? "−" : "+"}
                  </span>
                </button>

                {isOpen ? (
                  <p className="mt-3 border-t border-white/10 pt-3 text-sm leading-relaxed text-gray-300">
                    {item.a}
                  </p>
                ) : null}
              </div>
            )
          })}
        </div>
      </div>
    </>
  )
}
