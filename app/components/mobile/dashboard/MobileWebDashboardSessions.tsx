"use client"

import type {
  SessionBucketStats,
  SessionBuckets,
} from "@/app/components/dashboard/DashboardSessionChart"
import {
  DASHBOARD_SESSION_COLORS,
  type DashboardSessionBucket,
} from "@/lib/dashboardSessionBuckets"
import { formatCurrency } from "@/lib/formatCurrency"
import { formatSignedPnlDisplay } from "@/lib/formatDisplay"
import {
  MOBILE_WEB_SESSION_ORDER,
  mobileWebBarShare,
  mobileWebSessionTitle,
  mobileWebSessionWinRate,
} from "@/lib/mobileWebDashboardAnalytics"
import MobileWebDashboardEmptyCopy from "./MobileWebDashboardEmptyCopy"
import { mwDashMoneyClass, mwDashText } from "./mobileWebDashboardChrome"

type MobileWebDashboardSessionsProps = {
  sessionBuckets: SessionBuckets
  totalTrades?: number
}

function sessionHasActivity(buckets: SessionBuckets) {
  return MOBILE_WEB_SESSION_ORDER.some(
    (name) => buckets[name].totalTrades > 0
  )
}

function deriveSummary(buckets: SessionBuckets) {
  let totalTrades = 0
  let totalPnL = 0
  let best: DashboardSessionBucket | null = null
  let worst: DashboardSessionBucket | null = null
  let bestWin: DashboardSessionBucket | null = null
  let bestWinRate = -1

  for (const name of MOBILE_WEB_SESSION_ORDER) {
    const stats = buckets[name]
    totalTrades += stats.totalTrades
    totalPnL += stats.totalPnL
    if (stats.totalTrades <= 0) continue
    if (!best || stats.totalPnL > buckets[best].totalPnL) best = name
    if (!worst || stats.totalPnL < buckets[worst].totalPnL) worst = name
    const wr = mobileWebSessionWinRate(stats)
    if (wr > bestWinRate) {
      bestWinRate = wr
      bestWin = name
    }
  }

  return {
    totalTrades,
    totalPnL,
    avgPnL: totalTrades ? totalPnL / totalTrades : 0,
    best,
    worst,
    bestWin,
    bestWinRate: bestWinRate < 0 ? 0 : bestWinRate,
  }
}

function SessionBarRow({
  name,
  stats,
  maxAbs,
}: {
  name: DashboardSessionBucket
  stats: SessionBucketStats
  maxAbs: number
}) {
  const share = mobileWebBarShare(stats.totalPnL, maxAbs)
  const winRate = mobileWebSessionWinRate(stats)
  const barColor =
    stats.totalPnL > 0
      ? "var(--tt-positive, #3ddc97)"
      : stats.totalPnL < 0
        ? "var(--tt-negative, #ff7b72)"
        : "color-mix(in srgb, var(--tt-text) 18%, transparent)"

  return (
    <div className="flex flex-col gap-1">
      <div className="flex min-w-0 items-baseline gap-2">
        <span
          className="h-1.5 w-1.5 shrink-0 rounded-full"
          style={{ backgroundColor: DASHBOARD_SESSION_COLORS[name] }}
          aria-hidden
        />
        <span className={`min-w-0 flex-1 truncate text-[13px] ${mwDashText.muted}`}>
          {mobileWebSessionTitle(name)}
        </span>
        <span
          className={`shrink-0 text-[13px] font-semibold tabular-nums ${mwDashMoneyClass(stats.totalPnL)}`}
        >
          {formatSignedPnlDisplay(stats.totalPnL)}
        </span>
        <span className={`shrink-0 text-[11px] tabular-nums ${mwDashText.tertiary}`}>
          · {stats.totalTrades.toLocaleString()}
        </span>
      </div>
      <div className="flex h-2.5 w-full items-center">
        {stats.totalPnL < 0 ? (
          <div className="flex h-2.5 w-full justify-end">
            <div
              className="h-2.5 rounded-[4px]"
              style={{ width: `${share * 100}%`, backgroundColor: barColor }}
            />
          </div>
        ) : (
          <div
            className="h-2.5 rounded-[4px]"
            style={{
              width: stats.totalPnL === 0 ? 0 : `${share * 100}%`,
              backgroundColor: barColor,
            }}
          />
        )}
      </div>
      <p className={`text-[11px] tabular-nums ${mwDashText.tertiary}`}>
        {winRate.toFixed(0)}% win rate
      </p>
    </div>
  )
}

export default function MobileWebDashboardSessions({
  sessionBuckets,
  totalTrades = 0,
}: MobileWebDashboardSessionsProps) {
  if (totalTrades === 0 || !sessionHasActivity(sessionBuckets)) {
    return (
      <MobileWebDashboardEmptyCopy body="Tag sessions on trades to unlock your session breakdown." />
    )
  }

  const maxAbs = Math.max(
    1,
    ...MOBILE_WEB_SESSION_ORDER.map((name) =>
      Math.abs(sessionBuckets[name].totalPnL)
    )
  )
  const summary = deriveSummary(sessionBuckets)

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-col gap-3">
        {MOBILE_WEB_SESSION_ORDER.map((name) => (
          <SessionBarRow
            key={name}
            name={name}
            stats={sessionBuckets[name]}
            maxAbs={maxAbs}
          />
        ))}
      </div>

      <div className={`space-y-1 text-[12px] leading-snug ${mwDashText.muted}`}>
        {summary.best || summary.worst ? (
          <div className="flex flex-wrap gap-x-3 gap-y-0.5">
            {summary.best ? (
              <span className={mwDashText.positive}>
                Best {mobileWebSessionTitle(summary.best)} ·{" "}
                {formatCurrency(sessionBuckets[summary.best].totalPnL)}
              </span>
            ) : null}
            {summary.worst && summary.worst !== summary.best ? (
              <span className={mwDashText.negative}>
                Worst {mobileWebSessionTitle(summary.worst)} ·{" "}
                {formatCurrency(sessionBuckets[summary.worst].totalPnL)}
              </span>
            ) : null}
          </div>
        ) : null}
        <p className={mwDashText.tertiary}>
          {summary.totalTrades.toLocaleString()} trades · Avg{" "}
          <span className={mwDashMoneyClass(summary.avgPnL)}>
            {formatSignedPnlDisplay(summary.avgPnL)}
          </span>
          {summary.bestWin ? (
            <>
              {" "}
              · Best win {mobileWebSessionTitle(summary.bestWin)}{" "}
              {summary.bestWinRate.toFixed(0)}%
            </>
          ) : null}
        </p>
      </div>
    </div>
  )
}
