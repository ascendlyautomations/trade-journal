"use client"

import Link from "next/link"

export default function DemoBanner() {
  return (
    <div className="fixed top-16 left-0 right-0 z-[9998] border-b border-emerald-500/20 bg-gradient-to-r from-emerald-500/10 via-blue-500/10 to-transparent backdrop-blur-md">
      <div className="mx-auto flex max-w-6xl flex-col items-start justify-between gap-3 px-4 py-3 sm:flex-row sm:items-center md:px-6">
        <p className="text-sm text-gray-200">
          <span className="font-medium text-white">You&apos;re exploring the TradeTraxs Demo.</span>{" "}
          Create your own account to start tracking your trading journey.
        </p>
        <Link
          href="/login"
          className="shrink-0 rounded-lg bg-emerald-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-emerald-600"
        >
          Start Free Trial
        </Link>
      </div>
    </div>
  )
}
