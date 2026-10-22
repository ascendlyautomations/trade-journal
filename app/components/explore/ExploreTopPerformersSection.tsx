"use client"

import Link from "next/link"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import EmptyState from "@/app/components/ui/EmptyState"
import type { ExploreWeeklyTopPerformer } from "@/lib/exploreWeeklyTopPerformers"
import { profilePath } from "@/lib/profileRoutes"

const PANEL_CLASS =
  "rounded-xl border border-white/10 bg-white/5 p-2.5 backdrop-blur-md md:p-4"

const CATEGORY_TITLE: Record<ExploreWeeklyTopPerformer["category"], string> = {
  pnl: "Top P&L",
  rr: "Top R:R",
  winRate: "Highest Win Rate",
}

type Props = {
  performers: ExploreWeeklyTopPerformer[]
  periodTitle?: string
  periodSubtitle?: string
  /** When false after load, show empty only if performers is also empty. */
  hasLeaderboardPeriod?: boolean
  showSectionHeader?: boolean
  loading: boolean
  error: string | null
  onRetry: () => void
}

export default function ExploreTopPerformersSection({
  performers,
  periodTitle = "Top Performers This Week",
  periodSubtitle = "Calendar week rankings from public trades (all accounts)",
  hasLeaderboardPeriod = true,
  showSectionHeader = true,
  loading,
  error,
  onRetry,
}: Props) {
  const body = (
    <>

      {loading ? (
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <div
              key={i}
              className="h-28 animate-pulse rounded-xl border border-white/10 bg-white/5"
            />
          ))}
        </div>
      ) : error ? (
        <EmptyState
          title="Couldn't load top performers"
          description={error}
          className="py-6"
          action={
            <button
              type="button"
              onClick={onRetry}
              className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
            >
              Retry
            </button>
          }
        />
      ) : performers.length === 0 ? (
        <EmptyState
          title="No weekly leaders yet"
          description={
            hasLeaderboardPeriod
              ? "No qualifying traders in this period."
              : "Top performers appear when traders log qualifying public trades."
          }
          className="py-6"
        />
      ) : (
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
          {performers.map((performer) => {
            const displayName =
              performer.name?.trim() ||
              performer.username?.trim() ||
              "Trader"
            const href = profilePath({
              id: performer.userId,
              username: performer.username,
            })

            return (
              <Link
                key={performer.category}
                href={href}
                className="group flex flex-col gap-3 rounded-xl border border-white/10 bg-gradient-to-br from-white/10 to-white/[0.03] p-3 transition hover:border-blue-400/30 hover:bg-white/10"
              >
                <p className="text-xs font-semibold uppercase tracking-wide text-blue-300">
                  {CATEGORY_TITLE[performer.category]}
                </p>
                <div className="flex items-center gap-3">
                  <ProfileAvatarImg
                    src={performer.avatar_url}
                    className="h-11 w-11 shrink-0 border border-white/10"
                  />
                  <div className="min-w-0">
                    <p className="truncate font-semibold text-white group-hover:text-blue-100">
                      {displayName}
                    </p>
                    {performer.username ? (
                      <p className="truncate text-xs text-gray-400">
                        @{performer.username}
                      </p>
                    ) : null}
                  </div>
                </div>
                <div className="mt-auto border-t border-white/10 pt-2">
                  <p className="text-[11px] uppercase tracking-wide text-gray-500">
                    {performer.metricLabel}
                  </p>
                  <p className="text-lg font-semibold text-emerald-300">
                    {performer.metricDisplay}
                  </p>
                </div>
              </Link>
            )
          })}
        </div>
      )}
    </>
  )

  if (!showSectionHeader) {
    return body
  }

  return (
    <section className={PANEL_CLASS} aria-labelledby="explore-weekly-top-heading">
      <div className="mb-3 flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h2
            id="explore-weekly-top-heading"
            className="text-sm font-semibold text-white md:text-base"
          >
            {periodTitle}
          </h2>
          <p className="mt-0.5 text-xs text-gray-400">{periodSubtitle}</p>
        </div>
        <Link
          href="/leaderboard"
          className="shrink-0 rounded-lg border border-white/10 bg-white/5 px-3 py-1.5 text-xs font-semibold text-blue-300 transition hover:border-blue-400/30 hover:bg-white/10 hover:text-blue-200 md:text-sm"
        >
          View Leaderboard
        </Link>
      </div>
      {body}
    </section>
  )
}
