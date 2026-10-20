"use client"

import "../analyticsDesktopTheme.css"
import Link from "next/link"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import { fetchLeaderboardPayload } from "../../lib/leaderboardFetch"
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
  getDefaultLeaderboardCustomRange,
  type LeaderboardAccountTypeFilter,
  type LeaderboardChartRow,
  type LeaderboardView,
} from "../../lib/leaderboardChart"
import {
  formatLeaderboardChartTooltipMetric,
  leaderboardChartPlotRows,
  type LeaderboardChartTooltipMetricKey,
} from "@/lib/leaderboardChartPlot"
import {
  buildLeaderboardChartDataWithFallback,
  leaderboardTimeframeFallbackMessage,
} from "../../lib/leaderboardTimeframeFallback"
import { formatPnlCurrency } from "../../lib/formatMoney"
import { formatRR, formatSignedPnlDisplay, pnlTextClassName } from "@/lib/formatDisplay"
import { profilePath } from "@/lib/profileRoutes"
import EmptyState from "../components/ui/EmptyState"
import { SkeletonLeaderboardPage } from "../components/ui/skeletons"
import NativeIosPullToRefresh from "@/app/components/NativeIosPullToRefresh"
import NativeDateInput from "@/app/components/ui/NativeDateInput"
import { chartAxisTick, chartCartesianGridProps } from "@/lib/chartTheme"
import {
  readLeaderboardAggregate,
  writeLeaderboardAggregate,
} from "@/lib/leaderboardSessionCache"
import {
  leaderboardAggregateCacheKey,
  normalizeLeaderboardPayload,
  type LeaderboardPayload,
  type LeaderboardQuery,
} from "@/lib/leaderboardAggregate"
import {
  bootstrapRowsToProfiles,
  fetchLeaderboardBootstrapPage,
  leaderboardChartEligible,
  LEADERBOARD_AUDIENCE_OPTIONS,
  LEADERBOARD_BOOTSTRAP_TIMEFRAME_OPTIONS,
  LEADERBOARD_CATEGORY_OPTIONS,
  leaderboardTimeframeSelectValue,
  legacyViewForRpcChartTimeframe,
  newYorkTodayYmd,
  parseLeaderboardTimeframeSelectValue,
  type LeaderboardBootstrapAudience,
  type LeaderboardBootstrapCategory,
  type LeaderboardBootstrapRow,
  type LeaderboardPageTimeframe,
  usesLeaderboardBootstrapRankings,
} from "@/lib/leaderboardBootstrap"
import {
  leaderboardCategoryLabel,
  leaderboardTableRowsFromBootstrap,
  leaderboardTableRowsFromLegacy,
} from "@/lib/leaderboardPresentation"

type LeaderboardProfile = {
  id: string
  username: string | null
  name: string | null
  avatar_url: string | null
}

const LEADERBOARD_SELECT_CLASS =
  "tt-leaderboard-select-trigger flex w-full min-w-0 cursor-pointer items-center justify-between rounded border border-white/10 bg-[#1e293b] px-4 py-2 text-left text-sm text-white"

const LEADERBOARD_FILTER_SELECT_WRAPPER =
  "w-full min-w-0"

const LEADERBOARD_CATEGORY_SELECT_WRAPPER =
  "w-full min-w-0 lg:min-w-[12.5rem] lg:flex-[1.35]"

const LEADERBOARD_DATE_INPUT_CLASS =
  "h-11 rounded-xl border border-blue-400/20 bg-[#0b2345] shadow-inner shadow-black/20 transition hover:border-blue-300/40 focus-within:border-emerald-400/60 focus-within:ring-2 focus-within:ring-emerald-500/30"

const LEADERBOARD_EMPTY_DESCRIPTION =
  "There isn't enough leaderboard data for the selected timeframe."

const LEADERBOARD_EMPTY_HINT = "Try another timeframe or account filter."

const EMPTY_RANKED_TRADERS: LeaderboardPayload["rankedTraders"] = []

const LEADERBOARD_CHART_STROKE = {
  average: "#3b82f6",
  best: "#22c55e",
  worst: "#ef4444",
  you: "var(--tt-leaderboard-you-line, #ffffff)",
} as const

const LEADERBOARD_CHART_SERIES: {
  dataKey: keyof Pick<LeaderboardChartRow, "average" | "best" | "worst" | "you">
  name: string
  stroke: string
}[] = [
  { dataKey: "average", name: "Average", stroke: LEADERBOARD_CHART_STROKE.average },
  { dataKey: "best", name: "Best", stroke: LEADERBOARD_CHART_STROKE.best },
  { dataKey: "worst", name: "Worst", stroke: LEADERBOARD_CHART_STROKE.worst },
  { dataKey: "you", name: "You", stroke: LEADERBOARD_CHART_STROKE.you },
]

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

function LeaderboardChartLegend({ showYou }: { showYou: boolean }) {
  const items = LEADERBOARD_CHART_SERIES.filter(
    (series) => showYou || series.dataKey !== "you"
  )
  return (
    <ul className="tt-leaderboard-chart-legend flex flex-wrap justify-center gap-x-4 gap-y-1 pt-2">
      {items.map((series) => (
        <li
          key={series.dataKey}
          className="flex items-center gap-1.5 text-xs text-gray-300"
        >
          <span
            className="inline-block h-0.5 w-5 shrink-0 rounded-full"
            style={{ backgroundColor: series.stroke }}
            aria-hidden
          />
          {series.name}
        </li>
      ))}
      <li className="w-full basis-full text-center text-[11px] leading-snug text-gray-500">
        Days with 1 contributor: Best (green) only
      </li>
    </ul>
  )
}

function LeaderboardTooltip({
  active,
  payload,
  label,
  showYou,
}: {
  active?: boolean
  payload?: TooltipPayload[]
  label?: string
  showYou: boolean
}) {
  if (!active || !payload?.length) return null

  const row = payload[0]?.payload
  if (!row) return null

  const contributorCount = row.contributorCount ?? 0
  const seriesItems = LEADERBOARD_CHART_SERIES.filter(
    (series) => showYou || series.dataKey !== "you"
  )

  return (
    <div className="tt-leaderboard-chart-tooltip rounded border border-white/10 bg-[#0f172a] px-3 py-2 text-sm text-white shadow-lg">
      {label != null ? (
        <p className="tt-leaderboard-chart-tooltip-label mb-1 border-b border-white/10 pb-1 text-gray-300">
          {label}
        </p>
      ) : null}
      <p className="tt-leaderboard-chart-tooltip-meta mb-1 text-gray-400">
        Contributors: {contributorCount.toLocaleString()}
      </p>
      {seriesItems.map((series) => (
        <p
          key={series.dataKey}
          className="font-medium"
          style={{ color: series.stroke }}
        >
          {series.name}:{" "}
          {formatLeaderboardChartTooltipMetric(
            series.dataKey as LeaderboardChartTooltipMetricKey,
            row[series.dataKey],
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
  const [payload, setPayload] = useState<LeaderboardPayload | null>(null)
  const [tradesLoading, setTradesLoading] = useState(true)
  const [leaderboardLoadError, setLeaderboardLoadError] = useState<string | null>(
    null
  )
  const [pageTimeframe, setPageTimeframe] = useState<LeaderboardPageTimeframe>({
    kind: "rpc",
    value: "month",
  })
  const [category, setCategory] = useState<LeaderboardBootstrapCategory>("pnl")
  const [audience, setAudience] = useState<LeaderboardBootstrapAudience>("all")
  const [bootstrapRows, setBootstrapRows] = useState<LeaderboardBootstrapRow[]>(
    []
  )
  const [bootstrapNextCursor, setBootstrapNextCursor] = useState<string | null>(
    null
  )
  const [bootstrapLoadingMore, setBootstrapLoadingMore] = useState(false)
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
  const userId = user?.id ?? null
  const usesRpcRankings = usesLeaderboardBootstrapRankings(
    pageTimeframe,
    accountTypeFilter
  )
  const usesRpcRankingsEffective = usesRpcRankings && !isDemoModeActive()
  const chartSidecarEligible = leaderboardChartEligible(
    category,
    audience,
    accountTypeFilter,
    pageTimeframe
  )

  const legacyQueryView = useMemo((): LeaderboardView => {
    if (pageTimeframe.kind === "legacy") return pageTimeframe.value
    return legacyViewForRpcChartTimeframe(pageTimeframe.value)
  }, [pageTimeframe])

  const legacyCustomStart = useMemo(() => {
    if (pageTimeframe.kind === "rpc" && pageTimeframe.value === "today") {
      return newYorkTodayYmd()
    }
    return customRangeStart
  }, [customRangeStart, pageTimeframe])

  const legacyCustomEnd = useMemo(() => {
    if (pageTimeframe.kind === "rpc" && pageTimeframe.value === "today") {
      return newYorkTodayYmd()
    }
    return customRangeEnd
  }, [customRangeEnd, pageTimeframe])

  const loadLegacyPayload = useCallback(async () => {
    const queryKey = leaderboardAggregateCacheKey({
      view: legacyQueryView,
      accountType: accountTypeFilter,
      nowIso: new Date().toISOString(),
      customStartYmd: legacyCustomStart,
      customEndYmd: legacyCustomEnd,
      viewerId: userId,
    })
    const cached = normalizeLeaderboardPayload(readLeaderboardAggregate(queryKey))
    if (cached) {
      setPayload(cached)
    }

    const next = await fetchLeaderboardPayload({
      view: legacyQueryView,
      accountType: accountTypeFilter,
      nowIso: new Date().toISOString(),
      customStartYmd: legacyCustomStart,
      customEndYmd: legacyCustomEnd,
      viewerId: userId,
    })
    setPayload(next)
    writeLeaderboardAggregate(queryKey, next)
    return next
  }, [
    accountTypeFilter,
    legacyCustomEnd,
    legacyCustomStart,
    legacyQueryView,
    userId,
  ])

  const loadData = useCallback(async () => {
    if (isDemoModeActive()) {
      setTradesLoading(false)
      setLeaderboardLoadError(null)
      setBootstrapRows([])
      setBootstrapNextCursor(null)
      return
    }

    setLeaderboardLoadError(null)
    setTradesLoading(true)

    try {
      if (usesRpcRankings) {
        if (
          (audience === "friends" || audience === "following") &&
          !userId
        ) {
          setBootstrapRows([])
          setBootstrapNextCursor(null)
          setPayload(null)
          return
        }

        if (pageTimeframe.kind !== "rpc") return
        const bootstrapPromise = fetchLeaderboardBootstrapPage({
          timeframe: pageTimeframe.value,
          category,
          audience,
        })
        const legacyPromise = chartSidecarEligible
          ? loadLegacyPayload()
          : Promise.resolve(null)

        const [bootstrap, legacyPayload] = await Promise.all([
          bootstrapPromise,
          legacyPromise,
        ])
        setBootstrapRows(bootstrap.rows)
        setBootstrapNextCursor(bootstrap.nextCursor)
        setProfilesById((prev) => ({
          ...prev,
          ...bootstrapRowsToProfiles(bootstrap.rows),
        }))
        if (!legacyPayload && !chartSidecarEligible) {
          setPayload(null)
        }
      } else {
        setBootstrapRows([])
        setBootstrapNextCursor(null)
        await loadLegacyPayload()
      }
    } catch (error) {
      console.error("[leaderboard] loadData error:", error)
      if (usesRpcRankings) {
        setBootstrapRows([])
        setBootstrapNextCursor(null)
      } else {
        setPayload(null)
      }
      setLeaderboardLoadError(
        error instanceof Error
          ? error.message
          : "Couldn't load leaderboard data. Please try again."
      )
    } finally {
      setTradesLoading(false)
    }
  }, [
    audience,
    category,
    chartSidecarEligible,
    loadLegacyPayload,
    pageTimeframe,
    userId,
    usesRpcRankings,
  ])

  useEffect(() => {
    void loadData()
  }, [loadData])

  const loadMoreBootstrap = useCallback(async () => {
    if (
      !usesRpcRankings ||
      !bootstrapNextCursor ||
      bootstrapLoadingMore ||
      pageTimeframe.kind !== "rpc"
    ) {
      return
    }
    setBootstrapLoadingMore(true)
    try {
      const page = await fetchLeaderboardBootstrapPage({
        timeframe: pageTimeframe.value,
        category,
        audience,
        cursor: bootstrapNextCursor,
      })
      setBootstrapRows((prev) => [...prev, ...page.rows])
      setBootstrapNextCursor(page.nextCursor)
      setProfilesById((prev) => ({
        ...prev,
        ...bootstrapRowsToProfiles(page.rows),
      }))
    } catch (error) {
      console.error("[leaderboard] loadMore error:", error)
    } finally {
      setBootstrapLoadingMore(false)
    }
  }, [
    audience,
    bootstrapLoadingMore,
    bootstrapNextCursor,
    category,
    pageTimeframe,
    usesRpcRankings,
  ])

  const customRange = useMemo(
    () =>
      pageTimeframe.kind === "legacy" && pageTimeframe.value === "Custom"
        ? { startDate: customRangeStart, endDate: customRangeEnd }
        : undefined,
    [pageTimeframe, customRangeStart, customRangeEnd]
  )

  const customRangeInvalid = useMemo(() => {
    if (pageTimeframe.kind !== "legacy" || pageTimeframe.value !== "Custom") {
      return false
    }
    if (!customRangeStart.trim() || !customRangeEnd.trim()) return false
    return customRangeStart > customRangeEnd
  }, [pageTimeframe, customRangeStart, customRangeEnd])

  const demoPayload = useMemo(() => {
    if (!isDemoModeActive()) return null
    return buildLeaderboardChartDataWithFallback(
      getDemoLeaderboardTrades(),
      legacyQueryView,
      userId,
      customRange,
      accountTypeFilter
    )
  }, [accountTypeFilter, customRange, legacyQueryView, userId])

  const activePayload = demoPayload
    ? {
        ...demoPayload,
        profiles: {} as LeaderboardPayload["profiles"],
      }
    : payload

  const chartData = activePayload?.chartData ?? []
  const chartPlotData = useMemo(
    () => leaderboardChartPlotRows(chartData),
    [chartData]
  )
  const todayStats = activePayload?.todayStats ?? {
    yourTradeCount: 0,
    yourAvgPnl: 0,
    yourAvgRR: null,
    globalAvgPnl: 0,
    globalAvgRR: null,
    globalTradeCount: 0,
    percentileTopPct: userId ? "0.0" : "—",
  }
  const rankedTraders = useMemo(
    () => activePayload?.rankedTraders ?? EMPTY_RANKED_TRADERS,
    [activePayload?.rankedTraders]
  )
  const yourRank = activePayload?.yourRank ?? null
  const hasLegacyData = activePayload?.hasData ?? false
  const effectiveLegacyView = activePayload?.effectiveView ?? legacyQueryView

  const timeframeFallbackMessage = useMemo(() => {
    if (usesRpcRankings) return null
    return leaderboardTimeframeFallbackMessage(
      legacyQueryView,
      effectiveLegacyView
    )
  }, [effectiveLegacyView, legacyQueryView, usesRpcRankings])

  const tableRows = useMemo(() => {
    if (usesRpcRankingsEffective) {
      return leaderboardTableRowsFromBootstrap(bootstrapRows, category)
    }
    return leaderboardTableRowsFromLegacy(rankedTraders)
  }, [bootstrapRows, category, rankedTraders, usesRpcRankingsEffective])

  const rankedTraderIds = useMemo(
    () => tableRows.map((row) => row.userId),
    [tableRows]
  )

  const timeframeLabel = useMemo(() => {
    const match = LEADERBOARD_BOOTSTRAP_TIMEFRAME_OPTIONS.find(
      (option) =>
        leaderboardTimeframeSelectValue(option.timeframe) ===
        leaderboardTimeframeSelectValue(pageTimeframe)
    )
    if (match) return match.label
    return effectiveLegacyView
  }, [effectiveLegacyView, pageTimeframe])

  const viewerBootstrapRank = useMemo(() => {
    if (!userId || !usesRpcRankingsEffective) return null
    const index = bootstrapRows.findIndex((row) => row.profileId === userId)
    if (index < 0) return null
    return index + 1
  }, [bootstrapRows, userId, usesRpcRankingsEffective])

  const hasRankedRows = usesRpcRankingsEffective
    ? bootstrapRows.length > 0
    : hasLegacyData && rankedTraders.length > 0

  const rankedTraderIdsKey = useMemo(
    () => rankedTraderIds.join("\0"),
    [rankedTraderIds]
  )

  useEffect(() => {
    if (
      !isDemoModeActive() &&
      payload?.profiles &&
      Object.keys(payload.profiles).length > 0
    ) {
      setProfilesById((prev) =>
        prev === payload.profiles ? prev : payload.profiles
      )
      return
    }

    if (rankedTraderIds.length === 0) {
      setProfilesById((prev) =>
        Object.keys(prev).length === 0 ? prev : {}
      )
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
        setProfilesById((prev) =>
          Object.keys(prev).length === 0 ? prev : {}
        )
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
  }, [payload, rankedTraderIdsKey])

  const yAxisTickFormatter = useCallback((v: number) => {
    return formatPnlCurrency(Number(v), {
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
    })
  }, [])

  const showChart =
    chartSidecarEligible &&
    !tradesLoading &&
    !customRangeInvalid &&
    hasLegacyData &&
    chartData.length > 0

  const showLeaderboardContent =
    !tradesLoading && !customRangeInvalid && hasRankedRows

  const displayCategory: LeaderboardBootstrapCategory = usesRpcRankingsEffective
    ? category
    : "pnl"

  const needsSignInForAudience =
    usesRpcRankingsEffective &&
    (audience === "friends" || audience === "following") &&
    !userId

  const rankingsModeLabel = usesRpcRankingsEffective
    ? "Community rankings (all accounts)"
    : "Legacy window rankings (P&L, account/timeframe filters)"

  if (tradesLoading) {
    return (
      <>
        <div className="tt-phase3-dark min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 px-4 py-6 md:px-8 md:py-8">
          <SkeletonLeaderboardPage />
        </div>
      </>
    )
  }

  return (
    <>

      <NativeIosPullToRefresh
        onRefresh={async () => {
          await loadData()
        }}
      >
      <div
        data-tt-native-surface="leaderboard"
        className="tt-phase3-dark min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 px-4 py-6 md:px-8 md:py-8"
      >
        <div className="mx-auto max-w-7xl min-w-0 space-y-4">
          <h1 className="text-2xl font-semibold text-blue-300 md:text-3xl">
            Leaderboard
          </h1>

          <div className="tt-leaderboard-filter-bar w-full min-w-0 space-y-3">
            <div className="grid w-full min-w-0 grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.35fr)_minmax(0,1fr)] lg:gap-4">
              <CustomSelect
                value={leaderboardTimeframeSelectValue(pageTimeframe)}
                onChange={(val) => {
                  setPageTimeframe(parseLeaderboardTimeframeSelectValue(val))
                }}
                className={LEADERBOARD_FILTER_SELECT_WRAPPER}
                triggerClassName={LEADERBOARD_SELECT_CLASS}
                options={LEADERBOARD_BOOTSTRAP_TIMEFRAME_OPTIONS.map(
                  (option) => ({
                    label: option.label,
                    value: leaderboardTimeframeSelectValue(option.timeframe),
                  })
                )}
              />
              <CustomSelect
                value={category}
                onChange={(val) =>
                  setCategory(val as LeaderboardBootstrapCategory)
                }
                disabled={!usesRpcRankings}
                className={LEADERBOARD_CATEGORY_SELECT_WRAPPER}
                triggerClassName={LEADERBOARD_SELECT_CLASS}
                options={LEADERBOARD_CATEGORY_OPTIONS.map((option) => ({
                  label: option.label,
                  value: option.value,
                }))}
              />
              <CustomSelect
                value={accountTypeFilter}
                onChange={(val) =>
                  setAccountTypeFilter(val as LeaderboardAccountTypeFilter)
                }
                className={`${LEADERBOARD_FILTER_SELECT_WRAPPER} sm:col-span-2 lg:col-span-1`}
                triggerClassName={LEADERBOARD_SELECT_CLASS}
                options={[
                  { label: "All Accounts", value: "all" },
                  { label: "Live", value: "live" },
                  { label: "Funded", value: "funded" },
                  { label: "Eval", value: "eval" },
                ]}
              />
            </div>

            <div
              className="tt-leaderboard-filters flex w-full min-w-0 flex-wrap gap-2"
              role="group"
              aria-label="Audience"
            >
              {LEADERBOARD_AUDIENCE_OPTIONS.map((option) => {
                const selected = audience === option.value
                return (
                  <button
                    key={option.value}
                    type="button"
                    data-selected={selected ? "true" : "false"}
                    disabled={!usesRpcRankings}
                    onClick={() => setAudience(option.value)}
                    className="tt-leaderboard-audience-pill rounded-full border border-white/15 bg-white/5 px-3 py-1.5 text-xs font-semibold text-gray-200 transition hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    {option.label}
                  </button>
                )
              })}
            </div>
          </div>

          {!usesRpcRankings ? (
            <p className="text-sm text-amber-200/90">{rankingsModeLabel}</p>
          ) : null}

          {pageTimeframe.kind === "legacy" && pageTimeframe.value === "Custom" ? (
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

          {timeframeFallbackMessage && !tradesLoading && !leaderboardLoadError ? (
            <p className="text-sm text-blue-200/90">{timeframeFallbackMessage}</p>
          ) : null}

          {chartSidecarEligible || !usesRpcRankingsEffective ? (
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
                      onClick={() => void loadData()}
                      className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
                    >
                      Retry
                    </button>
                }
              />
            ) : needsSignInForAudience ? (
              <EmptyState
                title="Sign In Required"
                description="Friends and Following rankings require a signed-in account."
                className="border-0 bg-transparent py-6"
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
                  {usesRpcRankingsEffective && viewerBootstrapRank ? (
                    <div className="space-y-0.5">
                      <p className="text-lg font-semibold text-white">
                        #{viewerBootstrapRank} in loaded rankings
                      </p>
                      <p className="text-sm text-gray-400">
                        Load more to see deeper ranks
                      </p>
                    </div>
                  ) : yourRank ? (
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
          ) : null}

          {chartSidecarEligible ? (
          <div className="rounded-xl border border-white/10 bg-white/5 p-4 backdrop-blur-md md:p-6">
            <h2 className="text-lg font-semibold text-blue-300">
              Community Leaderboard
            </h2>
            <p className="mb-3 text-sm text-gray-400">
              Daily P&amp;L comparison (PnL · All audience · All accounts).
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
              <div className="tt-leaderboard-chart">
                <ResponsiveContainer width="100%" height={360}>
                  <LineChart data={chartPlotData}>
                    <CartesianGrid strokeDasharray="3 3" {...chartCartesianGridProps} />
                    <XAxis dataKey="label" {...chartAxisTick(12)} />
                    <YAxis
                      {...chartAxisTick(12)}
                      tickFormatter={yAxisTickFormatter}
                      width={72}
                    />
                    <Tooltip
                      content={(props) => (
                        <LeaderboardTooltip
                          active={props.active}
                          payload={
                            Array.isArray(props.payload)
                              ? (props.payload as TooltipPayload[])
                              : undefined
                          }
                          label={
                            typeof props.label === "string"
                              ? props.label
                              : undefined
                          }
                          showYou={Boolean(userId)}
                        />
                      )}
                    />
                    <Legend content={<LeaderboardChartLegend showYou={Boolean(userId)} />} />

                    <Line
                      type="monotone"
                      name="Best"
                      dataKey="bestPlot"
                      stroke={LEADERBOARD_CHART_STROKE.best}
                      dot={false}
                      connectNulls={false}
                      activeDot={{ r: 4, stroke: LEADERBOARD_CHART_STROKE.best, fill: LEADERBOARD_CHART_STROKE.best }}
                    />
                    <Line
                      type="monotone"
                      name="Worst"
                      dataKey="worstPlot"
                      stroke={LEADERBOARD_CHART_STROKE.worst}
                      dot={false}
                      connectNulls={false}
                      activeDot={{ r: 4, stroke: LEADERBOARD_CHART_STROKE.worst, fill: LEADERBOARD_CHART_STROKE.worst }}
                    />
                    <Line
                      type="monotone"
                      name="Average"
                      dataKey="averagePlot"
                      stroke={LEADERBOARD_CHART_STROKE.average}
                      dot={false}
                      connectNulls={false}
                      activeDot={{ r: 4, stroke: LEADERBOARD_CHART_STROKE.average, fill: LEADERBOARD_CHART_STROKE.average }}
                    />
                    {userId ? (
                      <Line
                        type="monotone"
                        name="You"
                        dataKey="youPlot"
                        stroke={LEADERBOARD_CHART_STROKE.you}
                        strokeWidth={3}
                        dot={false}
                        connectNulls={false}
                        activeDot={{
                          r: 4,
                          stroke: LEADERBOARD_CHART_STROKE.you,
                          fill: LEADERBOARD_CHART_STROKE.you,
                        }}
                      />
                    ) : null}
                  </LineChart>
                </ResponsiveContainer>
              </div>
            )}
          </div>
          ) : null}

          <div className="rounded-xl border border-white/10 bg-white/5 p-4 backdrop-blur-md md:p-6">
            <h2 className="mb-1 text-lg font-semibold text-blue-300">
              Top Traders — {leaderboardCategoryLabel(displayCategory)}
            </h2>
            <p className="mb-3 text-sm text-gray-400">
              {timeframeLabel}
              {usesRpcRankingsEffective
                ? ` · ${audience === "all" ? "All traders" : audience === "friends" ? "Friends" : "Following"}`
                : ` · ${effectiveLegacyView} legacy`}
            </p>

            {needsSignInForAudience ? (
              <EmptyState
                title="Sign In Required"
                description="Friends and Following rankings require a signed-in account."
                className="border-0 bg-transparent py-6"
              />
            ) : !showLeaderboardContent ? (
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
                      onClick={() => void loadData()}
                      className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
                    >
                      Retry
                    </button>
                  ) : undefined
                }
              />
            ) : (
              <>
                <div className="overflow-x-auto">
                  <table className="w-full min-w-[32rem] text-left text-sm">
                    <thead>
                      <tr className="border-b border-white/10 text-xs uppercase tracking-wide text-gray-400">
                        <th className="px-3 py-2 font-medium">Rank</th>
                        <th className="px-3 py-2 font-medium">Trader</th>
                        <th className="px-3 py-2 font-medium text-right">
                          {leaderboardCategoryLabel(displayCategory)}
                        </th>
                        <th className="px-3 py-2 font-medium text-right">
                          Details
                        </th>
                      </tr>
                    </thead>
                    <tbody>
                      {tableRows.map((row) => (
                        <tr
                          key={`${row.rank}-${row.userId}`}
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
                            className={`px-3 py-3 text-right font-semibold ${
                              displayCategory === "pnl" && row.pnlForColor != null
                                ? pnlTextClassName(row.pnlForColor)
                                : "text-gray-100"
                            }`}
                          >
                            {row.primaryMetric}
                          </td>
                          <td className="px-3 py-3 text-right text-gray-200">
                            {row.secondaryMetric}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                {usesRpcRankingsEffective && bootstrapNextCursor ? (
                  <div className="mt-4 flex justify-center">
                    <button
                      type="button"
                      disabled={bootstrapLoadingMore}
                      onClick={() => void loadMoreBootstrap()}
                      className="rounded-lg border border-white/15 bg-white/5 px-4 py-2 text-sm font-semibold text-white transition hover:bg-white/10 disabled:opacity-60"
                    >
                      {bootstrapLoadingMore ? "Loading…" : "Load more"}
                    </button>
                  </div>
                ) : null}
              </>
            )}
          </div>
        </div>
      </div>
      </NativeIosPullToRefresh>
    </>
  )
}
