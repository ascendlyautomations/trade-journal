"use client"

import Link from "next/link"
import { dashboardInsightCardClass } from "@/app/components/dashboard/dashboardInsightStyles"

type DashboardJournalEmptyStateProps = {
  onAddTrade: () => void
  onImportCsv: () => void
  className?: string
}

/**
 * Zero-trade dashboard hero — primary actions without replacing the full dashboard shell.
 */
export default function DashboardJournalEmptyState({
  onAddTrade,
  onImportCsv,
  className = "",
}: DashboardJournalEmptyStateProps) {
  return (
    <section
      className={`${dashboardInsightCardClass} relative overflow-hidden px-4 py-5 md:px-6 md:py-6 ${className}`}
      aria-labelledby="dashboard-journal-empty-heading"
    >
      <div
        className="pointer-events-none absolute inset-0 bg-gradient-to-br from-blue-500/10 via-transparent to-emerald-500/5"
        aria-hidden
      />
      <div className="relative">
        <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-blue-300/90 md:text-xs">
          Your journal
        </p>
        <h2
          id="dashboard-journal-empty-heading"
          className="mt-1 text-lg font-semibold text-white md:text-xl"
        >
          Start Your Trading Journal
        </h2>
        <p className="mt-1.5 max-w-xl text-sm leading-relaxed text-gray-300 md:text-[15px]">
          Log your first trade, import history, or connect a broker. Your stats,
          equity curve, and insights will fill in as you go — no sample data.
        </p>

        <div className="mt-4 flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-center md:mt-5">
          <button
            type="button"
            onClick={onAddTrade}
            className="inline-flex min-h-[44px] w-full items-center justify-center rounded-lg bg-blue-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-600 sm:w-auto"
          >
            Add Trade
          </button>
          <button
            type="button"
            onClick={onImportCsv}
            className="inline-flex min-h-[44px] w-full items-center justify-center rounded-lg border border-white/20 bg-white/10 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-white/15 sm:w-auto"
          >
            Import CSV
          </button>
          <Link
            href="/settings#broker-integrations"
            className="inline-flex min-h-[44px] w-full items-center justify-center rounded-lg border border-white/15 bg-white/5 px-4 py-2.5 text-sm font-semibold text-gray-100 transition hover:bg-white/10 sm:w-auto"
          >
            Connect Broker
          </Link>
        </div>

        <ul className="mt-4 flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-400 md:mt-5 md:text-[13px]">
          <li>Performance stats</li>
          <li className="hidden sm:list-item">·</li>
          <li>Equity curve</li>
          <li className="hidden sm:list-item">·</li>
          <li>Session analysis</li>
          <li className="hidden md:list-item">·</li>
          <li className="hidden md:list-item">Symbol insights</li>
        </ul>
      </div>
    </section>
  )
}
