"use client"

import { useState } from "react"
import {
  TRAXPRO_PLAN_NAME,
  TRAXPRO_TRIAL_LABEL,
} from "@/lib/traxProPricing"
import { FREE_PLAN_ACCOUNT_LIMIT } from "@/lib/tradingAccounts"

const faqs = [
  {
    q: "What is TradeTraxs?",
    a: "TradeTraxs is a trading journal and social platform where you can track your trades, analyze your performance, and share trades with others.",
  },
  {
    q: "Can I track multiple trading accounts?",
    a: `The Free plan includes up to ${FREE_PLAN_ACCOUNT_LIMIT} trading accounts. ${TRAXPRO_PLAN_NAME} includes unlimited trading accounts.`,
  },
  {
    q: "What does the Free plan include?",
    a: `Free includes: up to ${FREE_PLAN_ACCOUNT_LIMIT} trading accounts; unlimited trade logging; basic dashboard analytics; community access; trade rooms and messaging; public profiles and feed posts; and 1 lifetime CSV import. Upgrade to ${TRAXPRO_PLAN_NAME} for AI Analyst, Backtest Lab, Prop Firm Dashboard, advanced analytics, and unlimited CSV imports.`,
  },
  {
    q: "What stats does TradeTraxs show?",
    a: `You can see P&L, win rate, risk-reward ratio, session performance, equity curve, and more on the Free plan. Advanced dashboard insights (Performance Insights, Edge, Risk, and Behavior panels) require ${TRAXPRO_PLAN_NAME}.`,
  },
  {
    q: "Can I share my trades publicly?",
    a: "Yes. You can post trades to the feed and others can like and comment. Public sharing is included on the Free plan.",
  },
  {
    q: "Can I upload screenshots of my trades?",
    a: "Yes, you can attach screenshots to every trade you log.",
  },
  {
    q: "Can I import trades from a CSV?",
    a: `The Free plan includes 1 lifetime CSV import. ${TRAXPRO_PLAN_NAME} includes unlimited CSV imports.`,
  },
  {
    q: "Does TradeTraxs support funded accounts?",
    a: `Yes, you can mark accounts and trades as Eval, Funded, or Live. ${TRAXPRO_PLAN_NAME} includes Prop Firm Mode analytics to track rule progress.`,
  },
  {
    q: "Can I message other traders?",
    a: `Yes. You can send direct messages, comment on trades and posts, and participate in Trade Rooms on the Free plan. ${TRAXPRO_PLAN_NAME} adds premium analytics and AI tools.`,
  },
  {
    q: "Is there a leaderboard?",
    a: "Yes, you can see how you rank compared to other traders by P&L and other stats.",
  },
  {
    q: "Do I need to pay to use TradeTraxs?",
    a: `No. TradeTraxs has a generous Free plan. ${TRAXPRO_PLAN_NAME} starts at $23.99/month and includes a ${TRAXPRO_TRIAL_LABEL.toLowerCase()}.`,
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
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white px-6 py-12">
        <h1 className="mb-2 text-center text-3xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
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
