"use client"

import Navbar from "../components/Navbar"
import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "../../lib/supabaseClient"
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
  type LeaderboardView,
  type TradeForLeaderboard,
} from "../../lib/leaderboardChart"
import { formatPnlCurrency } from "../../lib/formatMoney"
import { formatRR, formatSignedPnlDisplay, pnlTextClassName } from "@/lib/formatDisplay"

type LeaderboardProfile = {
  id: string
  username: string | null
  name: string | null
  avatar_url: string | null
}

const LEADERBOARD_SELECT_CLASS =
  "w-full shrink-0 rounded border border-white/10 bg-[#1e293b] px-4 py-2 sm:w-auto"

const LEADERBOARD_DATE_INPUT_CLASS =
  "tt-timeframe-date h-11 w-full min-w-0 cursor-pointer rounded-xl border border-blue-400/20 bg-[#0b2345] px-3 py-2 text-sm text-white shadow-inner shadow-black/20 transition hover:border-blue-300/40 focus:border-emerald-400/60 focus:outline-none focus:ring-2 focus:ring-emerald-500/30 [color-scheme:dark]"

function openNativeDatePicker(input: HTMLInputElement) {
  try {
    input.showPicker()
  } catch {
    input.focus()
  }
}

type TooltipPayload = {
  name?: string
  value?: number
  dataKey?: string | number
  color?: string
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
  return (
    <div className="rounded border border-white/10 bg-[#0f172a] px-3 py-2 text-sm text-white shadow-lg">
      {label != null ? (
        <p className="mb-1 border-b border-white/10 pb-1 text-gray-300">{label}</p>
      ) : null}
      {payload.map((entry, i) => (
        <p key={String(entry.dataKey ?? i)} className="font-medium" style={{ color: entry.color }}>
          {entry.name ?? entry.dataKey}:{" "}
          {formatPnlCurrency(Number(entry.value), {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2,
          })}
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
    avatarUrl: profile?.avatar_url || "/default-avatar.png",
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

  return (
    <div className="flex min-w-0 items-center gap-3">
      <img
        src={avatarUrl}
        alt=""
        loading="lazy"
        decoding="async"
        className="h-9 w-9 shrink-0 rounded-full border border-white/10 object-cover"
        onError={(e) => {
          e.currentTarget.src = "/default-avatar.png"
        }}
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
    </div>
  )
}

export default function Leaderboard() {
  const router = useRouter()
  const [trades, setTrades] = useState<TradeForLeaderboard[]>([])
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
  }, [])

  async function fetchData() {
    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (user) setUserId(user.id)

    const PAGE_SIZE = 1000
    const allTrades: TradeForLeaderboard[] = []
    let from = 0

    while (true) {
      const to = from + PAGE_SIZE - 1
      const { data, error } = await supabase
        .from("trades")
        .select("user_id, pnl, rr, created_at, account_type, mode")
        .order("created_at", { ascending: true })
        .range(from, to)

      if (error) {
        console.error("[leaderboard] trade fetch error:", error)
        break
      }

      const batch = (data || []) as TradeForLeaderboard[]
      allTrades.push(...batch)

      if (batch.length < PAGE_SIZE) break
      from += PAGE_SIZE
    }

    setTrades(allTrades)

    if (allTrades.length > 0) {
      const earliest = allTrades[0]?.created_at
      const latest = allTrades[allTrades.length - 1]?.created_at
      console.log("[leaderboard] fetch", {
        totalTradesFetched: allTrades.length,
        earliestCreatedAt: earliest,
        latestCreatedAt: latest,
      })
    } else {
      console.log("[leaderboard] fetch", { totalTradesFetched: 0 })
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

  const goToProfile = useCallback(
    (profileUserId: string) => {
      router.push(`/profile/${profileUserId}`)
    },
    [router]
  )

  useEffect(() => {
    console.log("[leaderboard] render", {
      selectedView: view,
      chartDataLength: chartData.length,
      hasData,
      totalTradesFetched: trades.length,
      earliestCreatedAt: trades[0]?.created_at ?? null,
      latestCreatedAt:
        trades.length > 0 ? trades[trades.length - 1]?.created_at ?? null : null,
    })
  }, [trades, view, chartData.length, hasData])

  const yAxisTickFormatter = useCallback((v: number) => {
    return formatPnlCurrency(Number(v), {
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
    })
  }, [])

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 px-4 py-6 md:px-8 md:py-8">
        <div className="mx-auto max-w-7xl space-y-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <h1 className="bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-2xl font-semibold text-transparent md:text-3xl">
              Leaderboard
            </h1>
            <div className="flex w-full flex-col gap-3 sm:w-auto sm:flex-row">
              <select
                value={view}
                onChange={(e) => setView(e.target.value as LeaderboardView)}
                className={LEADERBOARD_SELECT_CLASS}
              >
                <option value="7D">7D</option>
                <option value="30D">30D</option>
                <option value="90D">90D</option>
                <option value="YTD">YTD</option>
                <option value="ALL">ALL</option>
                <option value="Custom">Custom</option>
              </select>
              <select
                value={accountTypeFilter}
                onChange={(e) =>
                  setAccountTypeFilter(e.target.value as LeaderboardAccountTypeFilter)
                }
                className={LEADERBOARD_SELECT_CLASS}
              >
                <option value="all">All Accounts</option>
                <option value="live">Live</option>
                <option value="funded">Funded</option>
                <option value="eval">Eval</option>
              </select>
            </div>
          </div>

          {view === "Custom" ? (
            <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
              <label className="flex min-w-0 flex-1 flex-col gap-1 text-sm">
                <span className="text-gray-400">Start Date</span>
                <input
                  type="date"
                  value={customRangeStart}
                  onFocus={(e) => openNativeDatePicker(e.currentTarget)}
                  onChange={(e) => setCustomRangeStart(e.target.value)}
                  className={LEADERBOARD_DATE_INPUT_CLASS}
                />
              </label>
              <label className="flex min-w-0 flex-1 flex-col gap-1 text-sm">
                <span className="text-gray-400">End Date</span>
                <input
                  type="date"
                  value={customRangeEnd}
                  onFocus={(e) => openNativeDatePicker(e.currentTarget)}
                  onChange={(e) => setCustomRangeEnd(e.target.value)}
                  className={LEADERBOARD_DATE_INPUT_CLASS}
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
              <p className="text-sm text-gray-400">
                Adjust the date range to view leaderboard data.
              </p>
            ) : !hasData ? (
              <p className="text-sm text-gray-400">
                No leaderboard data available for this timeframe.
              </p>
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
            <h2 className="mb-3 text-lg font-semibold text-blue-300">
              Performance Comparison
            </h2>

            <ResponsiveContainer width="100%" height={360}>
              {customRangeInvalid ? (
                <div className="flex h-full items-center justify-center text-sm text-gray-400">
                  Adjust the date range to view leaderboard data.
                </div>
              ) : !hasData ? (
                <div className="flex h-full items-center justify-center text-sm text-gray-400">
                  No leaderboard data available for this timeframe.
                </div>
              ) : (
                <LineChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#334155" />
                  <XAxis dataKey="label" stroke="#94a3b8" />
                  <YAxis stroke="#94a3b8" tickFormatter={yAxisTickFormatter} width={72} />
                  <Tooltip content={(props) => <LeaderboardTooltip {...props} />} />
                  <Legend />

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
              )}
            </ResponsiveContainer>
          </div>

          <div className="rounded-xl border border-white/10 bg-white/5 p-4 backdrop-blur-md md:p-6">
            <h2 className="mb-3 text-lg font-semibold text-blue-300">
              Top Traders ({view})
            </h2>

            {!hasData ? (
              <p className="text-sm text-gray-400">
                {customRangeInvalid
                  ? "Adjust the date range to view leaderboard data."
                  : "No leaderboard data available."}
              </p>
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
                        role="link"
                        tabIndex={0}
                        onClick={() => goToProfile(row.userId)}
                        onKeyDown={(e) => {
                          if (e.key === "Enter" || e.key === " ") {
                            e.preventDefault()
                            goToProfile(row.userId)
                          }
                        }}
                        className={`cursor-pointer border-b border-white/5 transition hover:bg-white/10 ${
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
    </>
  )
}
