"use client"

import { useState } from "react"
import {
  TRAXPRO_PLAN_NAME,
  TRAXPRO_TRIAL_LABEL,
} from "@/lib/traxProPricing"
import {
  formatPlanFeaturesList,
  TRADETRAXS_FREE_PLAN,
  TRADETRAXS_PRO_PLAN,
} from "@/lib/tradeTraxsPlans"
import { COMPANY_PAGE_TOP } from "@/lib/companyPageUi"

const faqs = [
  {
    q: "What is TradeTraxs?",
    a: "TradeTraxs is a trading journal and social platform where you can track your trades, analyze your performance, and share trades with others.",
  },
  {
    q: "Can I track multiple trading accounts?",
    a: `${TRADETRAXS_PRO_PLAN.name} includes unlimited trading accounts. ${TRADETRAXS_FREE_PLAN.name} is designed for getting started with manual trade journaling and community features.`,
  },
  {
    q: "What does the Free plan include?",
    a: `${TRADETRAXS_FREE_PLAN.description} Includes: ${formatPlanFeaturesList(TRADETRAXS_FREE_PLAN)}.`,
  },
  {
    q: "What does TradeTraxs Pro include?",
    a: `${TRADETRAXS_PRO_PLAN.description} Includes: ${formatPlanFeaturesList(TRADETRAXS_PRO_PLAN)}.`,
  },
  {
    q: "What stats does TradeTraxs show?",
    a: `${TRADETRAXS_FREE_PLAN.name} includes basic trading statistics. ${TRAXPRO_PLAN_NAME} unlocks advanced performance analytics, AI Trade Analyst, Backtest Lab, Prop Firm Mode, and advanced trade insights.`,
  },
  {
    q: "Can I share my trades publicly?",
    a: `Yes. You can post trades to the feed and others can like and comment. Public sharing is included on ${TRADETRAXS_FREE_PLAN.name}.`,
  },
  {
    q: "Can I upload screenshots of my trades?",
    a: `${TRAXPRO_PLAN_NAME} includes unlimited screenshots. You can attach screenshots when logging trades on Pro.`,
  },
  {
    q: "Can I import trades from a CSV?",
    a: `CSV import and advanced trade insights are included with ${TRAXPRO_PLAN_NAME}.`,
  },
  {
    q: "Does TradeTraxs support funded accounts?",
    a: `Yes. ${TRAXPRO_PLAN_NAME} includes Prop Firm Mode to track rule progress on Eval, Funded, and Live accounts.`,
  },
  {
    q: "Can I message other traders?",
    a: `${TRADETRAXS_FREE_PLAN.name} includes Trade Rooms and community features. ${TRAXPRO_PLAN_NAME} adds unlimited journaling, AI Trade Analyst, Backtest Lab, Prop Firm Mode, and advanced performance analytics.`,
  },
  {
    q: "Is there a leaderboard?",
    a: "Yes, you can see how you rank compared to other traders by P&L and other stats.",
  },
  {
    q: "Do I need to pay to use TradeTraxs?",
    a: `No. ${TRADETRAXS_FREE_PLAN.name} lets you explore the platform at no cost. ${TRAXPRO_PLAN_NAME} starts at $23.99/month and includes a ${TRAXPRO_TRIAL_LABEL.toLowerCase()}.`,
  },
  {
    q: "Is my data private?",
    a: "Yes, your private trade notes stay private unless you choose to share a trade publicly.",
  },
]

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
