"use client"

import Link from "next/link"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import Navbar from "../components/Navbar"
import FollowButton from "../components/FollowButton"
import EmptyState from "../components/ui/EmptyState"
import { SkeletonExplorePage, SkeletonTraderCard } from "../components/ui/skeletons"
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react"
import { supabase } from "../../lib/supabaseClient"
import {
  buildLeaderboardRankings,
  filterTradesForLeaderboardWindow,
  type TradeForLeaderboard,
} from "@/lib/leaderboardChart"
import {
  bioPreview,
  buildTradeSummaries,
  EXPLORE_ACTIVE_LIMIT,
  EXPLORE_NEW_LIMIT,
  EXPLORE_TOP_LIMIT,
  EXPLORE_TRADE_ROW_LIMIT,
  formatJoinedLabel,
  getExploreTradeWindowCutoff,
  mergeExploreProfiles,
  rankActiveTraders,
  type ExploreProfile,
  type ExploreTopView,
} from "@/lib/exploreDiscover"
import { formatPnlCurrency } from "@/lib/formatMoney"
import { formatRR, formatSignedPnlDisplay, pnlTextClassName } from "@/lib/formatDisplay"
import { profilePath } from "@/lib/profileRoutes"
import {
  getExploreTradesForView,
  readExploreSession,
  setExploreTradesForView,
  writeExploreSession,
} from "@/lib/exploreSessionCache"

type EnrichedTopTrader = {
  userId: string
  rank: number
  totalPnl: number
  tradeCount: number
  winRate: number | null
  avgRR: number | null
  profile?: ExploreProfile
}

const PROFILE_FIELDS =
  "id, username, name, avatar_url, bio, created_at, is_private" as const

const SEARCH_PROFILE_FIELDS =
  "id, username, name, avatar_url, is_private" as const

const SEARCH_MIN_CHARS = 2

const SECTION_PANEL =
  "rounded-xl border border-white/10 bg-white/10 p-2.5 backdrop-blur-md md:p-3"

const SELECT_CLASS =
  "h-[34px] shrink-0 rounded-md border border-white/10 bg-[#0f172a] px-3 py-1 text-sm text-white hover:bg-[#1e293b] focus:outline-none focus:ring-2 focus:ring-blue-500"

const SEARCH_INPUT_CLASS =
  "w-full rounded-xl border border-white/10 bg-black/30 p-3 text-sm text-white placeholder:text-gray-500 focus:border-blue-400/50 focus:outline-none focus:ring-2 focus:ring-blue-500/40"

async function fetchTradesForWindow(
  view: ExploreTopView
): Promise<TradeForLeaderboard[]> {
  const cutoff = getExploreTradeWindowCutoff(view)

  let query = supabase
    .from("trades")
    .select("user_id, pnl, rr, created_at")
    .eq("is_public", true)
    .order("created_at", { ascending: true })
    .limit(EXPLORE_TRADE_ROW_LIMIT)

  if (cutoff) {
    query = query.gte("created_at", cutoff)
  }

  const { data, error } = await query

  if (error) {
    console.error("[explore] trade fetch error:", error)
    return []
  }

  return (data || []) as TradeForLeaderboard[]
}

function getTraderDisplay(profile: ExploreProfile | undefined, userId: string) {
  const displayName =
    profile?.name?.trim() ||
    profile?.username?.trim() ||
    `Trader ${userId.slice(0, 6)}`
  const username = profile?.username?.trim() || null
  return {
    displayName,
    username,
    avatarUrl: profile?.avatar_url?.trim() || null,
  }
}

function TraderIdentity({
  profile,
  userId,
  subtitle,
  eagerAvatar = false,
}: {
  profile?: ExploreProfile
  userId: string
  subtitle?: string | null
  eagerAvatar?: boolean
}) {
  const { displayName, username, avatarUrl } = getTraderDisplay(profile, userId)

  const href = profilePath({ id: userId, username: profile?.username })

  return (
    <Link
      href={href}
      className="flex min-w-0 items-center gap-3 rounded-lg transition hover:opacity-90"
      onClick={(e) => e.stopPropagation()}
    >
      <ProfileAvatarImg
        src={avatarUrl}
        className="h-10 w-10 shrink-0 border border-white/10"
        priority={eagerAvatar}
      />
      <div className="min-w-0">
        <p className="truncate font-medium text-gray-100">{displayName}</p>
        {username ? (
          <p className="truncate text-xs text-gray-400">@{username}</p>
        ) : null}
        {subtitle ? (
          <p className="mt-0.5 line-clamp-2 text-xs text-gray-400">{subtitle}</p>
        ) : null}
      </div>
    </Link>
  )
}

function SectionHeading({
  title,
  description,
  action,
}: {
  title: string
  description?: string
  action?: ReactNode
}) {
  return (
    <div className="mb-2 flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h2 className="text-sm font-semibold text-blue-300">{title}</h2>
        {description ? (
          <p className="mt-0.5 text-xs text-gray-400">{description}</p>
        ) : null}
      </div>
      {action ? <div className="shrink-0">{action}</div> : null}
    </div>
  )
}

export default function ExplorePage() {
  const initialLoadDone = useRef(false)
  const [loading, setLoading] = useState(true)
  const [loadingTopView, setLoadingTopView] = useState(false)
  const [currentUserId, setCurrentUserId] = useState<string | null>(null)
  const [followingIds, setFollowingIds] = useState<Set<string>>(new Set())
  const [requestedIds, setRequestedIds] = useState<Set<string>>(new Set())
  const [followsYouIds, setFollowsYouIds] = useState<Set<string>>(new Set())
  const [profiles, setProfiles] = useState<ExploreProfile[]>([])
  const [trades, setTrades] = useState<TradeForLeaderboard[]>([])
  const [topView, setTopView] = useState<ExploreTopView>("30D")
  const [search, setSearch] = useState("")
  const [results, setResults] = useState<
    Pick<ExploreProfile, "id" | "username" | "name" | "avatar_url" | "is_private">[]
  >([])
  const [loadingSearch, setLoadingSearch] = useState(false)
  const [searchFinished, setSearchFinished] = useState(false)

  async function ensureTopTraderProfiles(
    topIds: string[],
    existing: ExploreProfile[]
  ) {
    const have = new Set(existing.map((p) => p.id))
    const missingTopIds = topIds.filter((id) => !have.has(id))
    if (missingTopIds.length === 0) return

    const { data } = await supabase
      .from("profiles")
      .select(PROFILE_FIELDS)
      .in("id", missingTopIds)
      .neq("is_private", true)

    if (data?.length) {
      setProfiles((prev) =>
        mergeExploreProfiles(prev, data as ExploreProfile[])
      )
    }
  }

  async function loadTradesForView(
    view: ExploreTopView,
    existingProfiles: ExploreProfile[],
    options?: { skipCache?: boolean }
  ) {
    if (!options?.skipCache) {
      const cachedTrades = getExploreTradesForView(view)
      if (cachedTrades) {
        setTrades(cachedTrades)
        const windowTrades = filterTradesForLeaderboardWindow(cachedTrades, view)
        const ranked = buildLeaderboardRankings(windowTrades, EXPLORE_TOP_LIMIT)
        await ensureTopTraderProfiles(
          ranked.map((row) => row.userId),
          existingProfiles
        )
        return
      }
    }

    const tradeRows = await fetchTradesForWindow(view)
    setTrades(tradeRows)
    setExploreTradesForView(view, tradeRows)

    const windowTrades = filterTradesForLeaderboardWindow(tradeRows, view)
    const ranked = buildLeaderboardRankings(windowTrades, EXPLORE_TOP_LIMIT)
    await ensureTopTraderProfiles(
      ranked.map((row) => row.userId),
      existingProfiles
    )
  }

  function restoreExploreSession(cached: NonNullable<ReturnType<typeof readExploreSession>>) {
    setCurrentUserId(cached.currentUserId)
    setProfiles(cached.profiles)
    setFollowingIds(new Set(cached.followingIds))
    setRequestedIds(new Set(cached.requestedIds))
    setFollowsYouIds(new Set(cached.followsYouIds))
    setTopView(cached.topView)
    const viewTrades = cached.tradesByView[cached.topView]
    if (viewTrades) setTrades(viewTrades)
    initialLoadDone.current = true
    setLoading(false)
    if (cached.scrollY > 0) {
      requestAnimationFrame(() => window.scrollTo(0, cached.scrollY))
    }
  }

  useEffect(() => {
    const cached = readExploreSession()
    if (cached) {
      restoreExploreSession(cached)
      return
    }
    void init()
  }, [])

  useEffect(() => {
    if (!initialLoadDone.current) return

    let cancelled = false

    async function reloadTopWindow() {
      setLoadingTopView(true)
      const snapshot = profiles
      await loadTradesForView(topView, snapshot)
      if (!cancelled) {
        setLoadingTopView(false)
        const current = readExploreSession()
        if (current) {
          writeExploreSession({ ...current, topView })
        }
      }
    }

    void reloadTopWindow()
    return () => {
      cancelled = true
    }
  }, [topView])

  useEffect(() => {
    const term = search.trim()
    if (term.length < SEARCH_MIN_CHARS) {
      setResults([])
      setLoadingSearch(false)
      setSearchFinished(false)
      return
    }

    const delayDebounce = setTimeout(async () => {
      setLoadingSearch(true)
      setSearchFinished(false)

      const { data } = await supabase
        .from("profiles")
        .select(SEARCH_PROFILE_FIELDS)
        .or(`username.ilike.%${term}%,name.ilike.%${term}%`)
        .not("username", "is", null)
        .neq("is_private", true)
        .limit(8)

      setResults(data || [])
      setLoadingSearch(false)
      setSearchFinished(true)
    }, 300)

    return () => clearTimeout(delayDebounce)
  }, [search])

  async function init() {
    setLoading(true)

    const {
      data: { user },
    } = await supabase.auth.getUser()
    setCurrentUserId(user?.id ?? null)

    const profilePoolLimit = EXPLORE_NEW_LIMIT + EXPLORE_ACTIVE_LIMIT

    const [profilesRes, followingRes, requestsRes, followsYouRes] =
      await Promise.all([
      supabase
        .from("profiles")
        .select(PROFILE_FIELDS)
        .not("username", "is", null)
        .neq("is_private", true)
        .order("created_at", { ascending: false })
        .limit(profilePoolLimit),
      user?.id
        ? supabase
            .from("followers")
            .select("following_id")
            .eq("follower_id", user.id)
        : Promise.resolve({ data: null }),
      user?.id
        ? supabase
            .from("follow_requests")
            .select("target_id")
            .eq("requester_id", user.id)
            .eq("status", "pending")
        : Promise.resolve({ data: null }),
      user?.id
        ? supabase
            .from("followers")
            .select("follower_id")
            .eq("following_id", user.id)
        : Promise.resolve({ data: null }),
    ])

    const pool = (profilesRes.data as ExploreProfile[]) || []
    setProfiles(pool)
    setFollowingIds(
      new Set((followingRes.data || []).map((row) => String(row.following_id)))
    )
    setRequestedIds(
      new Set((requestsRes.data || []).map((row) => String(row.target_id)))
    )
    setFollowsYouIds(
      new Set((followsYouRes.data || []).map((row) => String(row.follower_id)))
    )

    await loadTradesForView("30D", pool, { skipCache: !readExploreSession() })

    const followingIdsArr = (followingRes.data || []).map((row) =>
      String(row.following_id)
    )
    const requestedIdsArr = (requestsRes.data || []).map((row) =>
      String(row.target_id)
    )
    const followsYouIdsArr = (followsYouRes.data || []).map((row) =>
      String(row.follower_id)
    )
    const tradesByView = readExploreSession()?.tradesByView ?? {}

    writeExploreSession({
      currentUserId: user?.id ?? null,
      profiles: pool,
      followingIds: followingIdsArr,
      requestedIds: requestedIdsArr,
      followsYouIds: followsYouIdsArr,
      tradesByView,
      topView: "30D",
      scrollY: 0,
    })

    initialLoadDone.current = true
    setLoading(false)
  }

  useEffect(() => {
    const onScroll = () => {
      const cached = readExploreSession()
      if (!cached || !initialLoadDone.current) return
      writeExploreSession({ ...cached, scrollY: window.scrollY })
    }
    window.addEventListener("scroll", onScroll, { passive: true })
    return () => window.removeEventListener("scroll", onScroll)
  }, [])

  const profilesById = useMemo(() => {
    const map: Record<string, ExploreProfile> = {}
    for (const profile of profiles) map[profile.id] = profile
    return map
  }, [profiles])

  const windowTrades = useMemo(
    () => filterTradesForLeaderboardWindow(trades, topView),
    [trades, topView]
  )

  const windowTradeSummaries = useMemo(
    () => buildTradeSummaries(windowTrades),
    [windowTrades]
  )

  const topTraders = useMemo((): EnrichedTopTrader[] => {
    const ranked = buildLeaderboardRankings(windowTrades, EXPLORE_TOP_LIMIT)

    return ranked
      .filter((row) => profilesById[row.userId]?.is_private !== true)
      .map((row) => {
      const summary = windowTradeSummaries[row.userId]
      return {
        userId: row.userId,
        rank: row.rank,
        totalPnl: row.totalPnl,
        tradeCount: row.tradeCount,
        winRate:
          summary && summary.tradeCount > 0
            ? (summary.winCount / summary.tradeCount) * 100
            : null,
        avgRR: row.avgRR,
        profile: profilesById[row.userId],
      }
    })
  }, [windowTrades, windowTradeSummaries, profilesById])

  const topTraderIds = useMemo(
    () => new Set(topTraders.map((row) => row.userId)),
    [topTraders]
  )

  const activeTraders = useMemo(() => {
    const exclude = new Set(topTraderIds)
    if (currentUserId) exclude.add(currentUserId)
    return rankActiveTraders(profiles, windowTradeSummaries, {}, {
      excludeUserIds: exclude,
      limit: EXPLORE_ACTIVE_LIMIT,
      minScore: 3,
    })
  }, [profiles, windowTradeSummaries, topTraderIds, currentUserId])

  const newTraders = useMemo(() => {
    return profiles
      .filter(
        (p) =>
          p.username?.trim() &&
          p.id !== currentUserId &&
          p.is_private !== true
      )
      .slice(0, EXPLORE_NEW_LIMIT)
  }, [profiles, currentUserId])

  function handleFollowingChange(targetUserId: string, following: boolean) {
    setFollowingIds((prev) => {
      const next = new Set(prev)
      if (following) next.add(targetUserId)
      else next.delete(targetUserId)
      return next
    })
  }

  function handleRequestedChange(targetUserId: string, requested: boolean) {
    setRequestedIds((prev) => {
      const next = new Set(prev)
      if (requested) next.add(targetUserId)
      else next.delete(targetUserId)
      return next
    })
  }

  return (
    <>
      <Navbar />

      <div className="w-full text-white px-2 pb-3 pt-0 md:px-4 md:pb-10">
        <div className="relative z-0 mx-auto mt-2.5 flex w-full max-w-[1600px] flex-col gap-3 px-1 md:gap-4 md:px-6">
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-blue-300">
              Community
            </p>
            <h1 className="mt-0.5 bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-2xl font-semibold text-transparent md:text-3xl">
              Explore
            </h1>
            <p className="mt-1 text-sm text-gray-400">
              Search traders, find top performers, and discover active members.
            </p>
          </div>

          <section className={`${SECTION_PANEL} relative z-20 overflow-visible`}>
            <SectionHeading
              title="Search Traders"
              description="Find traders by username or display name."
            />

            <div className="relative overflow-visible">
              <input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search by username or display name…"
                className={SEARCH_INPUT_CLASS}
                aria-label="Search traders"
              />

              {search.trim().length > 0 &&
              search.trim().length < SEARCH_MIN_CHARS ? (
                <p className="mt-2 text-xs text-gray-500">
                  Type at least {SEARCH_MIN_CHARS} characters to search.
                </p>
              ) : null}

              {loadingSearch ? (
                <div className="mt-3 space-y-2">
                  {Array.from({ length: 3 }).map((_, i) => (
                    <SkeletonTraderCard key={i} />
                  ))}
                </div>
              ) : null}

              {searchFinished && search.trim().length >= SEARCH_MIN_CHARS &&
              results.length === 0 ? (
                <div className="mt-3">
                  <EmptyState
                    title="No traders found"
                    description={`No profiles match "${search.trim()}". Try a different username or display name.`}
                    className="py-8"
                  />
                </div>
              ) : null}

              {results.length > 0 ? (
                <div className="absolute z-[100] mt-2 w-full overflow-hidden rounded-xl border border-white/10 bg-[#0f172a] shadow-xl">
                  {results.map((user) => (
                    <div
                      key={user.id}
                      className="flex items-center justify-between gap-3 border-b border-white/5 px-3 py-2.5 transition last:border-b-0 hover:bg-white/5"
                    >
                      <TraderIdentity
                        profile={user as ExploreProfile}
                        userId={user.id}
                      />
                      <FollowButton
                        targetUserId={user.id}
                        currentUserId={currentUserId}
                        targetIsPrivate={user.is_private}
                        followingIds={followingIds}
                        requestedIds={requestedIds}
                        followsYouIds={followsYouIds}
                        onFollowingChange={handleFollowingChange}
                        onRequestedChange={handleRequestedChange}
                      />
                    </div>
                  ))}
                </div>
              ) : null}
            </div>
          </section>

          {loading ? (
            <SkeletonExplorePage />
          ) : (
            <>
              <section className={`${SECTION_PANEL} relative z-0`}>
                <SectionHeading
                  title="Top Traders"
                  description="Highest P&L in the selected timeframe."
                  action={
                    <select
                      value={topView}
                      onChange={(e) =>
                        setTopView(e.target.value as ExploreTopView)
                      }
                      className={SELECT_CLASS}
                      aria-label="Top traders timeframe"
                      disabled={loadingTopView}
                    >
                      <option value="30D">30D</option>
                      <option value="90D">90D</option>
                      <option value="YTD">YTD</option>
                      <option value="ALL">ALL</option>
                    </select>
                  }
                />

                {loadingTopView ? (
                  <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                    {Array.from({ length: 6 }).map((_, i) => (
                      <SkeletonTraderCard key={i} />
                    ))}
                  </div>
                ) : null}

                {!loadingTopView && topTraders.length === 0 ? (
                  <EmptyState
                    title="No top traders yet"
                    description="Traders will appear here once performance data is available for this timeframe."
                    className="py-8"
                  />
                ) : null}

                {!loadingTopView && topTraders.length > 0 ? (
                  <div className="space-y-2">
                    <div className="overflow-x-auto">
                      <table className="w-full min-w-[36rem] text-left text-sm">
                        <thead>
                          <tr className="border-b border-white/10 text-xs uppercase tracking-wide text-gray-400">
                            <th className="px-2 py-2 font-medium">Rank</th>
                            <th className="px-2 py-2 font-medium">Trader</th>
                            <th className="px-2 py-2 font-medium text-right">
                              P&amp;L
                            </th>
                            <th className="px-2 py-2 font-medium text-right">
                              Win %
                            </th>
                            <th className="px-2 py-2 font-medium text-right">
                              Trades
                            </th>
                            <th className="px-2 py-2 font-medium text-right">
                              Avg RR
                            </th>
                            <th className="px-2 py-2 font-medium text-right">
                              Follow
                            </th>
                          </tr>
                        </thead>
                        <tbody>
                          {topTraders.map((row, index) => (
                            <tr
                              key={row.userId}
                              className="border-b border-white/5 transition hover:bg-white/5"
                            >
                              <td className="px-2 py-2.5 font-semibold text-white">
                                #{row.rank}
                              </td>
                              <td className="max-w-[12rem] px-2 py-2.5 sm:max-w-none">
                                <TraderIdentity
                                  profile={row.profile}
                                  userId={row.userId}
                                  eagerAvatar={index < 3}
                                />
                              </td>
                              <td
                                className={`px-2 py-2.5 text-right font-semibold ${pnlTextClassName(row.totalPnl)}`}
                              >
                                {formatSignedPnlDisplay(row.totalPnl)}
                              </td>
                              <td className="px-2 py-2.5 text-right text-gray-200">
                                {row.winRate == null
                                  ? "—"
                                  : `${row.winRate.toFixed(1)}%`}
                              </td>
                              <td className="px-2 py-2.5 text-right text-gray-200">
                                {row.tradeCount.toLocaleString()}
                              </td>
                              <td className="px-2 py-2.5 text-right text-gray-200">
                                {row.avgRR == null ? "—" : formatRR(row.avgRR)}
                              </td>
                              <td className="px-2 py-2.5 text-right">
                                <FollowButton
                                  targetUserId={row.userId}
                                  currentUserId={currentUserId}
                                  targetIsPrivate={row.profile?.is_private}
                                  followingIds={followingIds}
                                  requestedIds={requestedIds}
                                  followsYouIds={followsYouIds}
                                  onFollowingChange={handleFollowingChange}
                                  onRequestedChange={handleRequestedChange}
                                />
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>

                    <div className="pt-1 text-right">
                      <Link
                        href="/leaderboard"
                        className="text-sm font-medium text-blue-300 transition hover:text-blue-200"
                      >
                        View Full Leaderboard →
                      </Link>
                    </div>
                  </div>
                ) : null}
              </section>

              <section className={SECTION_PANEL}>
                <SectionHeading
                  title="Discover Active Traders"
                  description="Traders with recent activity and completed profiles."
                />

                {activeTraders.length === 0 ? (
                  <EmptyState
                    title="No active traders to show"
                    description="Check back as more traders add profiles and log trades."
                    className="py-8"
                  />
                ) : (
                  <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
                    {activeTraders.map((profile) => {
                      const summary = windowTradeSummaries[profile.id]
                      const winRate =
                        summary && summary.tradeCount > 0
                          ? (summary.winCount / summary.tradeCount) * 100
                          : null

                      return (
                        <div
                          key={profile.id}
                          className="flex flex-col gap-2 rounded-xl border border-white/10 bg-white/5 p-3 transition hover:border-white/20 hover:bg-white/[0.07]"
                        >
                          <div className="flex items-start justify-between gap-2">
                            <TraderIdentity
                              profile={profile}
                              userId={profile.id}
                              subtitle={bioPreview(profile.bio)}
                            />
                            <FollowButton
                              targetUserId={profile.id}
                              currentUserId={currentUserId}
                              targetIsPrivate={profile.is_private}
                              followingIds={followingIds}
                              requestedIds={requestedIds}
                              followsYouIds={followsYouIds}
                              onFollowingChange={handleFollowingChange}
                              onRequestedChange={handleRequestedChange}
                            />
                          </div>
                          {summary && summary.tradeCount > 0 ? (
                            <div className="flex flex-wrap gap-2 text-xs">
                              <span className="rounded bg-white/10 px-2 py-0.5 text-gray-300">
                                {summary.tradeCount} trades
                              </span>
                              {winRate != null ? (
                                <span className="rounded bg-white/10 px-2 py-0.5 text-gray-300">
                                  {winRate.toFixed(1)}% win
                                </span>
                              ) : null}
                              <span
                                className={`rounded bg-white/10 px-2 py-0.5 ${pnlTextClassName(summary.totalPnl)}`}
                              >
                                {formatPnlCurrency(summary.totalPnl, {
                                  minimumFractionDigits: 0,
                                  maximumFractionDigits: 0,
                                })}
                              </span>
                            </div>
                          ) : (
                            <p className="text-xs text-gray-500">
                              Active on TradeTraxs
                            </p>
                          )}
                        </div>
                      )
                    })}
                  </div>
                )}
              </section>

              <section className={SECTION_PANEL}>
                <SectionHeading
                  title="New to TradeTraxs"
                  description="Recently joined traders on the platform."
                />

                {newTraders.length === 0 ? (
                  <EmptyState
                    title="No new traders yet"
                    description="New members will appear here as they join TradeTraxs."
                    className="py-8"
                  />
                ) : (
                  <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
                    {newTraders.map((profile) => (
                      <div
                        key={profile.id}
                        className="flex items-center justify-between gap-3 rounded-xl border border-white/10 bg-white/5 p-3 transition hover:border-white/20 hover:bg-white/[0.07]"
                      >
                        <TraderIdentity
                          profile={profile}
                          userId={profile.id}
                          subtitle={formatJoinedLabel(profile.created_at)}
                        />
                        <FollowButton
                          targetUserId={profile.id}
                          currentUserId={currentUserId}
                          targetIsPrivate={profile.is_private}
                          followingIds={followingIds}
                          requestedIds={requestedIds}
                          followsYouIds={followsYouIds}
                          onFollowingChange={handleFollowingChange}
                          onRequestedChange={handleRequestedChange}
                        />
                      </div>
                    ))}
                  </div>
                )}
              </section>
            </>
          )}
        </div>
      </div>
    </>
  )
}
