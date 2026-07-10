"use client"

import { useMemo, useState } from "react"
import Fuse, { type IFuseOptions } from "fuse.js"
import FaqQuestionModal from "@/app/components/marketing/FaqQuestionModal"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { TRADETRAXS_FAQ_ITEMS, type FaqItem } from "@/lib/faqContent"
import { COMPANY_PAGE_TOP } from "@/lib/companyPageUi"

const fuseOptions: IFuseOptions<FaqItem> = {
  includeScore: true,
  threshold: 0.42,
  ignoreLocation: true,
  keys: [
    { name: "question", weight: 0.7 },
    { name: "answer", weight: 0.3 },
  ],
}

export default function FAQPage() {
  const [query, setQuery] = useState("")
  const [openIndex, setOpenIndex] = useState<number | null>(null)
  const [questionModalOpen, setQuestionModalOpen] = useState(false)
  const { showPopup, feedbackModalProps } = useFeedbackPopup()

  const fuse = useMemo(
    () => new Fuse(TRADETRAXS_FAQ_ITEMS, fuseOptions),
    []
  )

  const trimmedQuery = query.trim()

  const visibleFaqs = useMemo(() => {
    if (!trimmedQuery) return TRADETRAXS_FAQ_ITEMS
    return fuse.search(trimmedQuery).map((result) => result.item)
  }, [fuse, trimmedQuery])

  function handleQueryChange(value: string) {
    setQuery(value)
    setOpenIndex(null)
  }

  return (
    <>
      <div
        className={`min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-6 pb-12 text-white ${COMPANY_PAGE_TOP}`}
      >
        <h1 className="mb-2 text-center text-3xl font-bold text-blue-300">
          FAQ
        </h1>
        <p className="mb-6 text-center text-sm text-gray-400">
          Quick answers about TradeTraxs
        </p>

        <div className="mx-auto mb-8 max-w-2xl">
          <label htmlFor="faq-search" className="sr-only">
            Search FAQ
          </label>
          <input
            id="faq-search"
            type="search"
            value={query}
            onChange={(e) => handleQueryChange(e.target.value)}
            placeholder="Ask a question..."
            autoComplete="off"
            className="w-full rounded-xl border border-white/10 bg-[#1e293b]/90 px-4 py-3 text-sm text-white placeholder:text-gray-500 shadow-lg shadow-black/20 outline-none transition focus:border-emerald-400/50 focus:ring-2 focus:ring-emerald-400/20"
          />
        </div>

        <div className="mx-auto max-w-2xl space-y-3">
          {visibleFaqs.length === 0 ? (
            <div className="rounded-xl border border-white/10 bg-[#1e293b]/90 px-6 py-10 text-center shadow-lg shadow-black/20">
              <p className="text-base font-medium text-white">
                We couldn&apos;t find an answer to your question.
              </p>
              <p className="mt-3 text-sm text-gray-400">Still need help?</p>
              <button
                type="button"
                onClick={() => setQuestionModalOpen(true)}
                className="mt-5 rounded-lg bg-blue-500 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-600"
              >
                Send a Question
              </button>
            </div>
          ) : (
            visibleFaqs.map((item, i) => {
              const isOpen = openIndex === i
              return (
                <div
                  key={item.question}
                  className="rounded-xl border border-white/10 bg-[#1e293b]/90 p-4 shadow-lg shadow-black/20 transition-colors hover:border-white/15"
                >
                  <button
                    type="button"
                    className="flex w-full cursor-pointer items-center justify-between gap-4 text-left"
                    onClick={() => setOpenIndex(isOpen ? null : i)}
                    aria-expanded={isOpen}
                  >
                    <span className="font-medium text-white">{item.question}</span>
                    <span
                      className="shrink-0 tabular-nums text-lg text-emerald-400/90"
                      aria-hidden
                    >
                      {isOpen ? "−" : "+"}
                    </span>
                  </button>

                  {isOpen ? (
                    <p className="mt-3 border-t border-white/10 pt-3 text-sm leading-relaxed text-gray-300">
                      {item.answer}
                    </p>
                  ) : null}
                </div>
              )
            })
          )}
        </div>
      </div>

      <FaqQuestionModal
        open={questionModalOpen}
        initialQuestion={trimmedQuery}
        onClose={() => setQuestionModalOpen(false)}
        onSuccess={() =>
          showPopup({
            type: "success",
            title: "Question Sent",
            message:
              "Thanks! We've received your question and will get back to you as soon as possible.",
          })
        }
      />
      <FeedbackModal {...feedbackModalProps} />
    </>
  )
}
