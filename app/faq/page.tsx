"use client"

import { useState } from "react"
import PublicNavbar from "../components/PublicNavbar"

const faqs = [
  {
    q: "What is TradeTrax?",
    a: "TradeTrax is a trading journal and social platform where you can track your trades, analyze your performance, and share trades with others.",
  },
  {
    q: "Can I track multiple trading accounts?",
    a: "Yeah, you can track multiple accounts and separate your stats for each one.",
  },
  {
    q: "What stats does TradeTrax show?",
    a: "You can see your P&L, win rate, risk-reward ratio, session performance, and more.",
  },
  {
    q: "Can I share my trades publicly?",
    a: "Yes, you can post your trades to the feed and others can like and comment on them.",
  },
  {
    q: "Can I upload screenshots of my trades?",
    a: "Yep, you can attach screenshots to every trade you log.",
  },
  {
    q: "Does TradeTrax support funded accounts?",
    a: "Yes, you can mark trades as Eval, Funded, or Live accounts.",
  },
  {
    q: "Can I message other traders?",
    a: "Yes, you can send direct messages and create group chats with other users.",
  },
  {
    q: "Is there a leaderboard?",
    a: "Yeah, you can see how you rank compared to other traders.",
  },
  {
    q: "Do I need to pay to use TradeTrax?",
    a: "There are free features, and premium features are available with a subscription.",
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
      <PublicNavbar />
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white px-6 py-12">
        <h1 className="mb-2 text-center text-3xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
          FAQ
        </h1>
        <p className="mb-10 text-center text-sm text-gray-400">
          Quick answers about TradeTrax
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
