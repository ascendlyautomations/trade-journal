"use client"

import Link from "next/link"
import { useTradingPreferenceDiscovery } from "@/lib/analytics/useTradingPreferenceDiscovery"

const preferencesHref = "/settings#trading-analytics"

type Props = {
  userId: string | null | undefined
  hasTrade?: boolean
  tradesReady?: boolean
  /** Dashboard shows the one-time invite and the quieter card. Other pages show only the small invitation. */
  surface: "dashboard" | "analytics"
  blocked?: boolean
}

export default function TradingPreferenceDiscovery({
  userId,
  hasTrade,
  tradesReady,
  surface,
  blocked = false,
}: Props) {
  const discovery = useTradingPreferenceDiscovery({ userId, hasTrade, tradesReady })
  const placement = surface === "dashboard" ? discovery.dashboardPlacement : discovery.placement
  if (blocked || placement == null) return null
  if (surface === "analytics" && placement !== "quiet") return null

  if (placement === "firstTrade") {
    return (
      <section
        className="mt-4 rounded-2xl border border-white/10 bg-white/5 p-4 md:mt-6"
        aria-labelledby="analytics-pref-invite-title"
      >
        <h2 id="analytics-pref-invite-title" className="text-base font-semibold text-white">
          Personalize Your Analytics
        </h2>
        <p className="mt-1 text-sm leading-relaxed text-gray-300">
          Setting your personal trading rules improves performance insights and recommendations.
        </p>
        <div className="mt-3 flex flex-wrap gap-2">
          <Link
            href={preferencesHref}
            onClick={() => void discovery.record("skipped")}
            className="rounded-lg bg-blue-600 px-3 py-2 text-sm font-semibold text-white hover:bg-blue-500"
          >
            Personalize
          </Link>
          <button
            type="button"
            onClick={() => void discovery.record("skipped")}
            className="rounded-lg px-3 py-2 text-sm font-medium text-gray-300 hover:bg-white/10"
          >
            Maybe Later
          </button>
        </div>
      </section>
    )
  }

  return (
    <section className="mt-4 flex items-start justify-between gap-3 rounded-xl border border-white/10 bg-white/[0.03] px-3 py-2.5 md:mt-6">
      <div className="min-w-0">
        <p className="text-sm text-gray-200">Get insights based on your trading rules.</p>
        <Link
          href={preferencesHref}
          className="mt-1 inline-block text-sm font-semibold text-blue-300 hover:text-blue-200"
        >
          Set Up Preferences
        </Link>
      </div>
      <button
        type="button"
        aria-label="Dismiss analytics preferences invitation"
        onClick={() => void discovery.record("dismissed")}
        className="shrink-0 rounded-md px-2 py-1 text-sm text-gray-400 hover:bg-white/10 hover:text-white"
      >
        Dismiss
      </button>
    </section>
  )
}
