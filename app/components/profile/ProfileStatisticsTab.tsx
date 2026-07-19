"use client"

import dynamic from "next/dynamic"
import { memo, type ReactNode } from "react"
import { formatPnlCurrency } from "@/lib/formatMoney"

const ProfileEquityLineChart = dynamic(
  () => import("@/app/components/profile/ProfileEquityLineChart"),
  {
    loading: () => (
      <div className="h-full min-h-[280px] animate-pulse rounded-lg bg-white/5" />
    ),
  }
)

export type ProfileStatisticsMode = "all" | "eval" | "funded" | "live"

type SessionBreakdownRow = {
  label: "NY" | "London" | "Asia"
  count: number
  pct: number
}

type ProfileStatisticsTabProps = {
  canView: boolean
  loading: boolean
  selectedMode: ProfileStatisticsMode
  onModeChange: (mode: ProfileStatisticsMode) => void
  filteredTradesCount: number
  statsVisible: boolean
  profitFactor: number | null
  averageWinner: number | null
  averageLoser: number | null
  profitPerTrade: number | null
  biggestWin: number
  biggestLoss: number | null
  longTrades: number
  maxWinStreak: number
  maxLossStreak: number
  sessionTotal: number
  sessionBreakdown: SessionBreakdownRow[]
  currentEquity: number
  equityData: Array<{ index: number; equity: number }>
  equityChartNarrow: boolean
}

function formatCurrency(value: number) {
  return `${value < 0 ? "-" : ""}$${Math.abs(value).toLocaleString(undefined, {
    maximumFractionDigits: 2,
  })}`
}

function formatMoney(value: number) {
  return value < 0
    ? `-$${Math.abs(value).toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`
    : `$${value.toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`
}

function Stat({
  title,
  value,
  positive,
}: {
  title: string
  value: ReactNode
  positive?: boolean
}) {
  let color = "text-gray-100"
  if (positive === true) color = "text-green-400"
  if (positive === false) color = "text-red-400"

  return (
    <div className="flex h-full flex-col items-center justify-center gap-1 rounded-xl border border-white/10 bg-white/5 p-6 text-center">
      <p className="text-xs text-blue-300">{title}</p>
      <p className={`text-lg font-semibold tabular-nums ${color}`}>{value}</p>
    </div>
  )
}

function ProfileStatisticsTab({
  canView,
  loading,
  selectedMode,
  onModeChange,
  filteredTradesCount,
  statsVisible,
  profitFactor,
  averageWinner,
  averageLoser,
  profitPerTrade,
  biggestWin,
  biggestLoss,
  longTrades,
  maxWinStreak,
  maxLossStreak,
  sessionTotal,
  sessionBreakdown,
  currentEquity,
  equityData,
  equityChartNarrow,
}: ProfileStatisticsTabProps) {
  return (
    <div className="space-y-6">
      {!canView ? (
        <div className="rounded-xl border border-white/10 bg-white/5 p-6 py-16 text-center">
          <p className="text-lg text-gray-100">Private Profile</p>
          <p className="mt-2 text-sm text-gray-400">
            Follow this user to see their trades and stats.
          </p>
        </div>
      ) : loading ? (
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
            {Array.from({ length: 8 }).map((_, i) => (
              <div
                key={i}
                className="h-24 animate-pulse rounded-xl border border-white/10 bg-white/5"
              />
            ))}
          </div>
          <div className="h-72 animate-pulse rounded-xl border border-white/10 bg-white/5" />
        </div>
      ) : (
        <>
          <div className="mb-4 flex items-center justify-between">
            <div className="flex flex-wrap items-center gap-2 md:gap-3">
              {(
                [
                  { id: "all", label: "All" },
                  { id: "eval", label: "Eval" },
                  { id: "funded", label: "Funded" },
                  { id: "live", label: "Live" },
                ] as const
              ).map(({ id, label }) => (
                <button
                  key={id}
                  type="button"
                  onClick={() => onModeChange(id)}
                  className={`px-4 py-1.5 rounded-lg text-sm font-medium transition ${
                    selectedMode === id
                      ? "bg-blue-500 text-white"
                      : "bg-white/5 text-white/70 hover:bg-white/10"
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>
            <div />
          </div>

          {filteredTradesCount === 0 ? (
            <p className="text-sm text-gray-400">
              No trades for this filter selection
            </p>
          ) : null}

          <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
            <Stat
              title="Profit Factor"
              value={
                statsVisible
                  ? profitFactor == null
                    ? "—"
                    : profitFactor.toLocaleString(undefined, {
                        minimumFractionDigits: 0,
                        maximumFractionDigits: 2,
                      })
                  : "—"
              }
              positive={profitFactor != null ? profitFactor >= 1 : undefined}
            />
            <Stat
              title="Avg Winner"
              value={
                statsVisible && averageWinner != null
                  ? formatCurrency(averageWinner)
                  : "—"
              }
              positive
            />
            <Stat
              title="Avg Loser"
              value={
                statsVisible && averageLoser != null
                  ? formatCurrency(averageLoser)
                  : "—"
              }
              positive={false}
            />
            <Stat
              title="Profit / Trade"
              value={
                statsVisible && profitPerTrade != null
                  ? formatCurrency(profitPerTrade)
                  : "—"
              }
              positive={
                profitPerTrade != null ? profitPerTrade >= 0 : undefined
              }
            />
            <Stat
              title="Biggest Win"
              value={formatPnlCurrency(biggestWin)}
              positive
            />
            <Stat
              title="Biggest Loss"
              value={
                biggestLoss != null ? formatPnlCurrency(biggestLoss) : "—"
              }
              positive={false}
            />
            <Stat title="Long Trades" value={longTrades} />
            <Stat
              title="Largest Streaks"
              value={`W${maxWinStreak} / L${maxLossStreak}`}
            />
          </div>

          <div className="rounded-xl border border-white/10 bg-white/5 p-4 md:p-5">
            <div className="mb-3 flex items-center justify-between">
              <h3 className="text-base font-semibold text-white">
                Trading Sessions
              </h3>
              <p className="text-xs text-gray-400">
                {sessionTotal > 0
                  ? `${sessionTotal} trades tagged`
                  : "No session data"}
              </p>
            </div>
            {sessionBreakdown.length === 0 ? (
              <p className="text-sm text-gray-400">
                Add session tags to trades to unlock this breakdown.
              </p>
            ) : (
              <div className="space-y-2.5">
                {sessionBreakdown.map((row) => (
                  <div key={row.label} className="space-y-1">
                    <div className="flex items-center justify-between text-sm">
                      <span className="font-medium text-gray-200">
                        {row.label}
                      </span>
                      <span className="tabular-nums text-gray-300">
                        {row.pct.toFixed(0)}%
                      </span>
                    </div>
                    <div className="h-2 overflow-hidden rounded-full bg-white/10">
                      <div
                        className="h-full rounded-full bg-gradient-to-r from-blue-500 to-emerald-400"
                        style={{
                          width: `${Math.max(4, Math.round(row.pct))}%`,
                        }}
                      />
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className="rounded-xl border border-white/10 bg-white/5 p-4 md:p-6">
            <div className="mb-3 flex flex-col gap-1 sm:mb-4 sm:flex-row sm:items-end sm:justify-between">
              <h2 className="text-lg font-semibold text-white">Equity Curve</h2>
              {filteredTradesCount > 0 ? (
                <p
                  className={`text-lg font-bold tabular-nums sm:text-xl ${
                    currentEquity >= 0 ? "text-green-400" : "text-red-400"
                  }`}
                >
                  {formatMoney(currentEquity)}
                </p>
              ) : null}
            </div>

            <div
              className={`w-full md:h-64 ${
                equityChartNarrow
                  ? "h-[min(52vw,340px)] min-h-[280px]"
                  : "h-72"
              }`}
            >
              <ProfileEquityLineChart
                data={equityData}
                narrow={equityChartNarrow}
              />
            </div>
          </div>
        </>
      )}
    </div>
  )
}

export default memo(ProfileStatisticsTab)
