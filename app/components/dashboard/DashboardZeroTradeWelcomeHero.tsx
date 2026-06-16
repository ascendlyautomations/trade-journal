"use client"

import Link from "next/link"

export type DashboardZeroTradeWelcomeHeroProps = {
  onImportCsv: () => void
}

export default function DashboardZeroTradeWelcomeHero({
  onImportCsv,
}: DashboardZeroTradeWelcomeHeroProps) {
  return (
    <div className="rounded-xl border border-white/10 bg-white/5 p-6 backdrop-blur-md md:p-8">
      <h2 className="bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-2xl font-semibold text-transparent md:text-3xl">
        Welcome to TradeTraxs
      </h2>
      <p className="mt-3 text-base font-medium text-gray-100 md:text-lg">
        Track every trade.
        <br />
        Discover your edge.
        <br />
        Improve your performance.
      </p>
      <p className="mt-3 max-w-2xl text-sm text-gray-400 md:text-base">
        Get started by logging your first trade or importing your trading history.
      </p>
      <div className="mt-6 flex flex-wrap items-center gap-3">
        <Link
          href="/app"
          className="rounded-lg bg-emerald-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-emerald-600"
        >
          Add Trade
        </Link>
        <button
          type="button"
          onClick={onImportCsv}
          className="rounded-lg border border-white/20 bg-white/10 px-4 py-2 text-sm font-semibold text-white transition hover:bg-white/15"
        >
          Import CSV
        </button>
      </div>
      <div className="mt-8 border-t border-white/10 pt-6">
        <p className="text-sm font-medium text-gray-300">
          After your first trade you&apos;ll unlock:
        </p>
        <ul className="mt-3 space-y-2 text-sm text-gray-400">
          <li>• Performance statistics</li>
          <li>• Equity curve tracking</li>
          <li>• Session &amp; weekday analysis</li>
          <li>• Symbol performance insights</li>
        </ul>
      </div>
    </div>
  )
}
