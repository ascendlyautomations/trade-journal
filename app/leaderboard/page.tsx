"use client"

import Link from "next/link"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import { useCallback, useEffect, useMemo, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import { fetchLeaderboardTrades } from "../../lib/leaderboardFetch"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { getDemoLeaderboardTrades } from "@/lib/demo/demoLeaderboard"
import { getDemoProfileById } from "@/lib/demo/demoProfile"
import { useUserProfile } from "@/lib/UserProfileProvider"
import CustomSelect from "@/app/components/CustomSelect"
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
  ResponsiveContainer,
  Legend,
} from "recharts"
import {
  buildLeaderboardChartData,
  getDefaultLeaderboardCustomRange,
  type LeaderboardAccountTypeFilter,
  type LeaderboardChartRow,
  type LeaderboardView,
  type TradeForLeaderboard,
} from "../../lib/leaderboardChart"
import { formatPnlCurrency } from "../../lib/formatMoney"
import { formatRR, formatSignedPnlDisplay, pnlTextClassName } from "@/lib/formatDisplay"
import { profilePath } from "@/lib/profileRoutes"
import EmptyState from "../components/ui/EmptyState"
import { SkeletonLeaderboardPage } from "../components/ui/skeletons"
import NativeIosPullToRefresh from "@/app/components/NativeIosPullToRefresh"
import NativeDateInput from "@/app/components/ui/NativeDateInput"
import {
  chartAxisTick,
  chartCartesianGridProps,
  READABLE_CHART_TICK,
} from "@/lib/chartTheme"

type LeaderboardProfile = {
  id: string
  username: string | null
  name: string | null
  avatar_url: string | null
}

const LEADERBOARD_SELECT_CLASS =
  "flex w-full shrink-0 cursor-pointer items-center justify-between rounded border border-white/10 bg-[#1e293b] px-4 py-2 text-left text-sm text-white sm:w-auto"

const LEADERBOARD_DATE_INPUT_CLASS =
  "h-11 rounded-xl border border-blue-400/20 bg-[#0b2345] shadow-inner shadow-black/20 transition hover:border-blue-300/40 focus-within:border-emerald-400/60 focus-within:ring-2 focus-within:ring-emerald-500/30"

const LEADERBOARD_EMPTY_DESCRIPTION =
  "There isn't enough leaderboard data for the selected timeframe."

const LEADERBOARD_EMPTY_HINT = "Try another timeframe or account filter."

function leaderboardEmptyDescription(): string {
  return `${LEADERBOARD_EMPTY_DESCRIPTION} ${LEADERBOARD_EMPTY_HINT}`
}

type TooltipPayload = {
  name?: string
  value?: number
  dataKey?: string | number
  color?: string
  payload?: LeaderboardChartRow
}

function formatLeaderboardTooltipMetric(
  dataKey: string | number | undefined,
  value: number | undefined,
  contributorCount: number
): string {
  const key = String(dataKey ?? "")

  if (key === "you") {
    return formatPnlCurrency(Number(value ?? 0), {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })
  }

  if (contributorCount === 0) return "N/A"
  if (key === "worst" && contributorCount === 1) return "N/A"

  return formatPnlCurrency(Number(value ?? 0), {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
}

function LeaderboardTooltip({
  active,
  payload,
  label,
}: {
  active?: boolean
  payload?: TooltipPayload[]
  label?: string
}) {
  if (!active || !payload?.length) return null

  const contributorCount = payload[0]?.payload?.contributorCount ?? 0

  return (
    <div className="rounded border border-white/10 bg-[#0f172a] px-3 py-2 text-sm text-white shadow-lg">
      {label != null ? (
        <p className="mb-1 border-b border-white/10 pb-1 text-gray-300">{label}</p>
      ) : null}
      <p className="mb-1 text-gray-400">
        Contributors: {contributorCount.toLocaleString()}
      </p>
      {payload.map((entry, i) => (
        <p key={String(entry.dataKey ?? i)} className="font-medium" style={{ color: entry.color }}>
          {entry.name ?? entry.dataKey}:{" "}
          {formatLeaderboardTooltipMetric(
            entry.dataKey,
            entry.value,
            contributorCount
          )}
        </p>
      ))}
    </div>
  )
}

function formatTraderLabel(userId: string): string {
  if (userId.length <= 12) return userId
  return `${userId.slice(0, 8)}…`
}

function getTraderDisplay(
  profile: LeaderboardProfile | undefined,
  userId: string
) {
  const displayName =
    profile?.name?.trim() ||
    profile?.username?.trim() ||
    formatTraderLabel(userId)
  const username = profile?.username?.trim() || null
  return {
    displayName,
    username,
    avatarUrl: profile?.avatar_url || null,
  }
}

function LeaderboardTraderCell({
  profile,
  userId,
  isYou,
}: {
  profile: LeaderboardProfile | undefined
  userId: string
  isYou: boolean
}) {
  const { displayName, username, avatarUrl } = getTraderDisplay(profile, userId)
  const href = profilePath({ id: userId, username: profile?.username })

  return (
    <Link
      href={href}
      className="flex min-w-0 items-center gap-3 rounded-lg transition hover:opacity-90"
    >
      <ProfileAvatarImg
        src={avatarUrl}
        className="h-9 w-9 shrink-0 border border-white/10"
      />
      <div className="min-w-0">
        <div className="flex min-w-0 items-center gap-2">
          <p className="truncate font-medium text-gray-100">{displayName}</p>
          {isYou ? (
            <span className="shrink-0 text-xs text-blue-300">(You)</span>
          ) : null}
          {/* Future: badges / verified / rank achievements */}
        </div>
        {username ? (
          <p className="truncate text-xs text-gray-400">@{username}</p>
        ) : null}
      </div>
    </Link>
  )
}

export default function Leaderboard() {
  const { user } = useUserProfile()
  const [trades, setTrades] = useState<TradeForLeaderboard[]>([])
  const [tradesLoading, setTradesLoading] = useState(true)
  const [leaderboardLoadError, setLeaderboardLoadError] = useState<string | null>(
    null
  )
  const [userId, setUserId] = useState<string | null>(null)
  const [view, setView] = useState<LeaderboardView>("7D")
  const [accountTypeFilter, setAccountTypeFilter] =
    useState<LeaderboardAccountTypeFilter>("all")
  const defaultCustomRange = useMemo(() => getDefaultLeaderboardCustomRange(), [])
  const [customRangeStart, setCustomRangeStart] = useState(
    defaultCustomRange.startDate
  )
  const [customRangeEnd, setCustomRangeEnd] = useState(defaultCustomRange.endDate)
  const [profilesById, setProfilesById] = useState<
    Record<string, LeaderboardProfile>
  >({})

  useEffect(() => {
    fetchData()
  }, [user?.id])

  async function fetchData() {
    setTradesLoading(true)
    setLeaderboardLoadError(null)
    try {
      if (isDemoModeActive()) {
        setUserId(user?.id ?? null)
        setTrades(getDemoLeaderboardTrades())
        return
      }

      setUserId(user?.id ?? null)

      const allTrades = await fetchLeaderboardTrades()

      setTrades(allTrades)
    } catch (error) {
      console.error("[leaderboard] fetchData error:", error)
      setTrades([])
      setLeaderboardLoadError(
        error instanceof Error
          ? error.message
          : "Couldn't load leaderboard data. Please try again."
      )
    } finally {
      setTradesLoading(false)
    }
  }

  const customRange = useMemo(
    () =>
      view === "Custom"
        ? { startDate: customRangeStart, endDate: customRangeEnd }
        : undefined,
    [view, customRangeStart, customRangeEnd]
  )

  const customRangeInvalid = useMemo(() => {
    if (view !== "Custom") return false
    if (!customRangeStart.trim() || !customRangeEnd.trim()) return false
    return customRangeStart > customRangeEnd
  }, [view, customRangeStart, customRangeEnd])

  const { chartData, todayStats, rankedTraders, yourRank, hasData } = useMemo(
    () =>
      buildLeaderboardChartData(
        trades,
        view,
        userId,
        customRange,
        accountTypeFilter
      ),
    [trades, view, userId, customRange, accountTypeFilter]
  )

  const rankedTraderIds = useMemo(
    () => rankedTraders.map((row) => row.userId),
    [rankedTraders]
  )

  useEffect(() => {
    if (rankedTraderIds.length === 0) {
      setProfilesById({})
      return
    }

    let cancelled = false

    async function fetchProfiles() {
      if (isDemoModeActive()) {
        const map: Record<string, LeaderboardProfile> = {}
        for (const id of rankedTraderIds) {
          const profile = getDemoProfileById(id)
          if (profile) {
            map[id] = {
              id: profile.id,
              username: profile.username,
              name: profile.name,
              avatar_url: profile.avatar_url,
            }
          }
        }
        if (!cancelled) setProfilesById(map)
        return
      }

      const { data, error } = await supabase
        .from("profiles")
        .select("id, username, name, avatar_url")
        .in("id", rankedTraderIds)

      if (cancelled) return

      if (error) {
        console.error("[leaderboard] profile fetch error:", error)
        setProfilesById({})
        return
      }

      const map: Record<string, LeaderboardProfile> = {}
      for (const row of data || []) {
        map[String(row.id)] = row as LeaderboardProfile
      }
      setProfilesById(map)
    }

    void fetchProfiles()

    return () => {
      cancelled = true
    }
  }, [rankedTraderIds])

  const yAxisTickFormatter = useCallback((v: number) => {
    return formatPnlCurrency(Number(v), {
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
    })
  }, [])

  const showChart =
    !tradesLoading && !customRangeInvalid && hasData && chartData.length > 0

  const showLeaderboardContent =
    !tradesLoading && !customRangeInvalid && hasData

  if (tradesLoading) {
    return (
      <>
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 px-4 py-6 md:px-8 md:py-8">
          <SkeletonLeaderboardPage />
        </div>
      </>
    )
  }

  return (
    <>

      <NativeIosPullToRefresh
        onRefresh={async () => {
          await fetchData()
        }}
      >
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 px-4 py-6 md:px-8 md:py-8">
        <div className="mx-auto max-w-7xl space-y-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <h1 className="hidden text-2xl font-semibold text-blue-300 md:block md:text-3xl">
              Leaderboard
            </h1>
            <div className="flex w-full flex-col gap-3 sm:w-auto sm:flex-row">
              <CustomSelect
                value={view}
                onChange={(val) => setView(val as LeaderboardView)}
                className="sm:w-auto"
                triggerClassName={LEADERBOARD_SELECT_CLASS}
                options={[
                  { label: "7D", value: "7D" },
                  { label: "30D", value: "30D" },
                  { label: "90D", value: "90D" },
                  { label: "YTD", value: "YTD" },
                  { label: "ALL", value: "ALL" },
                  { label: "Custom", value: "Custom" },
                ]}
              />
              <CustomSelect
                value={accountTypeFilter}
                onChange={(val) =>
                  setAccountTypeFilter(val as LeaderboardAccountTypeFilter)
                }
                className="sm:w-auto"
                triggerClassName={LEADERBOARD_SELECT_CLASS}
                options={[
                  { label: "All Accounts", value: "all" },
                  { label: "Live", value: "live" },
                  { label: "Funded", value: "funded" },
                  { label: "Eval", value: "eval" },
                ]}
              />
            </div>
          </div>

          {view === "Custom" ? (
            <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
              <label className="flex min-w-0 flex-1 flex-col gap-1 text-sm">
                <span className="text-gray-400">Start Date</span>
                <NativeDateInput
                  value={customRangeStart}
                  onChange={(e) => setCustomRangeStart(e.target.value)}
                  className={LEADERBOARD_DATE_INPUT_CLASS}
                  aria-label="Start date"
                />
              </label>
              <label className="flex min-w-0 flex-1 flex-col gap-1 text-sm">
                <span className="text-gray-400">End Date</span>
                <NativeDateInput
                  value={customRangeEnd}
                  onChange={(e) => setCustomRangeEnd(e.target.value)}
                  className={LEADERBOARD_DATE_INPUT_CLASS}
                  aria-label="End date"
                />
              </label>
            </div>
          ) : null}

          {customRangeInvalid ? (
            <p className="text-sm text-amber-300">
              Start date must be on or before end date.
            </p>
          ) : null}

          <div className="rounded-xl border border-white/10 bg-white/5 p-4 backdrop-blur-md md:p-5">
            {customRangeInvalid ? (
              <EmptyState
                title="Invalid Date Range"
                description="Start date must be on or before end date. Adjust the range to view leaderboard data."
                className="border-0 bg-transparent py-6"
              />
            ) : leaderboardLoadError ? (
              <EmptyState
                title="Couldn't Load Leaderboard"
                description={leaderboardLoadError}
                className="border-0 bg-transparent py-6"
                action={
                  <button
                    type="button"
                    onClick={() => void fetchData()}
                    className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
                  >
                    Retry
                  </button>
                }
              />
            ) : !showLeaderboardContent ? (
              <EmptyState
                title="No Leaderboard Data"
                description={leaderboardEmptyDescription()}
                className="border-0 bg-transparent py-6"
              />
            ) : (
              <div className="grid grid-cols-1 gap-4 md:grid-cols-3 md:gap-6">
                <div className="md:border-r md:border-white/10 md:pr-6">
                  <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-blue-300">
                    Your Rank
                  </h2>
                  {yourRank ? (
                    <div className="space-y-0.5">
                      <p className="text-lg font-semibold text-white">
                        #{yourRank.rank} of {yourRank.totalTraders} Traders
                      </p>
                      <p className="text-sm text-blue-300">
                        Top {yourRank.percentileTopPct}%
                      </p>
                    </div>
                  ) : (
                    <p className="text-sm text-gray-400">—</p>
                  )}
                </div>

                <div className="md:border-r md:border-white/10 md:pr-6">
                  <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-blue-300">
                    Your Stats
                  </h2>
                  <dl className="space-y-1 text-sm">
                    <div className="flex justify-between gap-3">
                      <dt className="text-gray-400">P&amp;L</dt>
                      <dd
                        className={`font-semibold ${yourRank ? pnlTextClassName(yourRank.totalPnl) : "text-gray-200"}`}
                      >
                        {yourRank
                          ? formatSignedPnlDisplay(yourRank.totalPnl)
                          : "—"}
                      </dd>
                    </div>
                    <div className="flex justify-between gap-3">
                      <dt className="text-gray-400">Trades</dt>
                      <dd className="font-medium text-gray-100">
                        {(yourRank?.tradeCount ?? todayStats.yourTradeCount).toLocaleString()}
                      </dd>
                    </div>
                    <div className="flex justify-between gap-3">
                      <dt className="text-gray-400">Avg RR</dt>
                      <dd className="font-medium text-gray-100">
                        {todayStats.yourAvgRR === null
                          ? "—"
                          : formatRR(todayStats.yourAvgRR)}
                      </dd>
                    </div>
                  </dl>
                </div>

                <div>
                  <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-blue-300">
                    Global Stats
                  </h2>
                  <dl className="space-y-1 text-sm">
                    <div className="flex justify-between gap-3">
                      <dt className="text-gray-400">Avg P&amp;L</dt>
                      <dd className="font-medium text-gray-100">
                        {formatPnlCurrency(todayStats.globalAvgPnl)}
                      </dd>
                    </div>
                    <div className="flex justify-between gap-3">
                      <dt className="text-gray-400">Avg RR</dt>
                      <dd className="font-medium text-gray-100">
                        {todayStats.globalAvgRR === null
                          ? "—"
                          : formatRR(todayStats.globalAvgRR)}
                      </dd>
                    </div>
                    <div className="flex justify-between gap-3">
                      <dt className="text-gray-400">Total Trades</dt>
                      <dd className="font-medium text-gray-100">
                        {todayStats.globalTradeCount.toLocaleString()}
                      </dd>
                    </div>
                  </dl>
                </div>
              </div>
            )}
          </div>

          <div className="rounded-xl border border-white/10 bg-white/5 p-4 backdrop-blur-md md:p-6">
            <h2 className="text-lg font-semibold text-blue-300">
              Community Leaderboard
            </h2>
            <p className="mb-3 text-sm text-gray-400">
              Performance comparison of traders with public profiles.
            </p>

            {customRangeInvalid ? (
              <EmptyState
                title="Invalid Date Range"
                description="Start date must be on or before end date. Adjust the range to view performance data."
                className="border-0 bg-transparent py-10"
              />
            ) : !showChart ? (
              <EmptyState
                title="No Performance Data Available"
                description={leaderboardEmptyDescription()}
                className="border-0 bg-transparent py-10"
              />
            ) : (
              <ResponsiveContainer width="100%" height={360}>
                <LineChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" {...chartCartesianGridProps} />
                  <XAxis
                    dataKey="label"
                    stroke={READABLE_CHART_TICK}
                    tick={{ fill: READABLE_CHART_TICK, fontSize: 12 }}
                  />
                  <YAxis
                    {...chartAxisTick(12)}
                    tickFormatter={yAxisTickFormatter}
                    width={72}
                  />
                  <Tooltip content={(props) => <LeaderboardTooltip {...props} />} />
                  <Legend
                    formatter={(value) => (
                      <span className="text-xs text-gray-300">{value}</span>
                    )}
                  />

                  <Line
                    type="monotone"
                    name="Average"
                    dataKey="average"
                    stroke="#3b82f6"
                    dot={false}
                  />
                  <Line
                    type="monotone"
                    name="Best"
                    dataKey="best"
                    stroke="#22c55e"
                    dot={false}
                  />
                  <Line
                    type="monotone"
                    name="Worst"
                    dataKey="worst"
                    stroke="#f87171"
                    dot={false}
                  />
                  <Line
                    type="monotone"
                    name="You"
                    dataKey="you"
                    stroke="#ffffff"
                    strokeWidth={3}
                    dot={false}
                  />
                </LineChart>
              </ResponsiveContainer>
            )}
          </div>

          <div className="rounded-xl border border-white/10 bg-white/5 p-4 backdrop-blur-md md:p-6">
            <h2 className="mb-3 text-lg font-semibold text-blue-300">
              Top Traders ({view})
            </h2>

            {!showLeaderboardContent ? (
              <EmptyState
                title={
                  leaderboardLoadError
                    ? "Couldn't Load Leaderboard"
                    : customRangeInvalid
                      ? "Invalid Date Range"
                      : "No Traders Ranked"
                }
                description={
                  leaderboardLoadError
                    ? leaderboardLoadError
                    : customRangeInvalid
                      ? "Start date must be on or before end date. Adjust the range to view leaderboard data."
                      : leaderboardEmptyDescription()
                }
                className="border-0 bg-transparent py-6"
                action={
                  leaderboardLoadError ? (
                    <button
                      type="button"
                      onClick={() => void fetchData()}
                      className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
                    >
                      Retry
                    </button>
                  ) : undefined
                }
              />
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[32rem] text-left text-sm">
                  <thead>
                    <tr className="border-b border-white/10 text-xs uppercase tracking-wide text-gray-400">
                      <th className="px-3 py-2 font-medium">Rank</th>
                      <th className="px-3 py-2 font-medium">Trader</th>
                      <th className="px-3 py-2 font-medium text-right">P&amp;L</th>
                      <th className="px-3 py-2 font-medium text-right">Trades</th>
                      <th className="px-3 py-2 font-medium text-right">Avg RR</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rankedTraders.map((row) => (
                      <tr
                        key={row.userId}
                        className={`border-b border-white/5 transition hover:bg-white/10 ${
                          row.userId === userId ? "bg-white/5" : ""
                        }`}
                      >
                        <td className="px-3 py-3 font-semibold text-white">
                          #{row.rank}
                        </td>
                        <td className="max-w-[12rem] px-3 py-3 sm:max-w-none">
                          <LeaderboardTraderCell
                            profile={profilesById[row.userId]}
                            userId={row.userId}
                            isYou={row.userId === userId}
                          />
                        </td>
                        <td
                          className={`px-3 py-3 text-right font-semibold ${pnlTextClassName(row.totalPnl)}`}
                        >
                          {formatSignedPnlDisplay(row.totalPnl)}
                        </td>
                        <td className="px-3 py-3 text-right text-gray-200">
                          {row.tradeCount.toLocaleString()}
                        </td>
                        <td className="px-3 py-3 text-right text-gray-200">
                          {row.avgRR === null ? "—" : formatRR(row.avgRR)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>
      </div>
      </NativeIosPullToRefresh>
    </>
  )
}
