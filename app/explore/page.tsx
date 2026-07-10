"use client"

import Link from "next/link"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import FollowButton from "../components/FollowButton"
import ExploreDiscoverBar from "../components/explore/ExploreDiscoverBar"
import ExploreTraderCard from "../components/explore/ExploreTraderCard"
import EmptyState from "../components/ui/EmptyState"
import { SkeletonExplorePage, SkeletonTraderCard } from "../components/ui/skeletons"
import { useEffect, useMemo, useRef, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import {
  buildPostSummaries,
  buildTradeSummaries,
  buildTraderTradeMeta,
  enrichExploreProfilesWithSocialCounts,
  EXPLORE_TRADE_ROW_LIMIT,
  fetchExploreSocialCounts,
  mergeExploreProfiles,
  rankExploreDiscoverList,
  type ExploreProfile,
} from "@/lib/exploreDiscover"
import {
  categoryTabFromTraderType,
  discoverFilterAvailability,
  EXPLORE_DEFAULT_FILTERS,
  filterExploreProfiles,
  type ExploreDiscoverFilters,
} from "@/lib/exploreFilters"
import { profilePath } from "@/lib/profileRoutes"
import { readExploreSession, writeExploreSession } from "@/lib/exploreSessionCache"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import {
  getDemoExploreFollowingIds,
  getDemoExploreFollowsYouIds,
  getDemoExploreProfiles,
  getDemoExploreTradeMetaRows,
  searchDemoExploreProfiles,
} from "@/lib/demo/demoExplore"
import { useUserProfile } from "@/lib/UserProfileProvider"

const EXPLORE_PAGE_SIZE = 16

const PROFILE_FIELDS =
  "id, username, name, avatar_url, bio, created_at, is_private, trader_type, trading_style, trading_model, primary_market, started_trading" as const

const SEARCH_PROFILE_FIELDS =
  "id, username, name, avatar_url, is_private" as const

const SEARCH_MIN_CHARS = 2

const PANEL_CLASS =
  "rounded-xl border border-white/10 bg-white/10 p-2.5 backdrop-blur-md md:p-3"

const SEARCH_INPUT_CLASS =
  "w-full rounded-xl border border-white/10 bg-black/30 p-3 text-sm text-white placeholder:text-gray-500 focus:border-blue-400/50 focus:outline-none focus:ring-2 focus:ring-blue-500/40"

type TradeMetaRow = {
  user_id: string
  session?: string | null
  ticker?: string | null
  created_at?: string
}

export default function ExplorePage() {
  const { user, profile: viewerProfile } = useUserProfile()
  const initialLoadDone = useRef(false)
  const defaultCategorySet = useRef(false)
  const [loading, setLoading] = useState(true)
  const [currentUserId, setCurrentUserId] = useState<string | null>(null)
  const [followingIds, setFollowingIds] = useState<Set<string>>(new Set())
  const [requestedIds, setRequestedIds] = useState<Set<string>>(new Set())
  const [followsYouIds, setFollowsYouIds] = useState<Set<string>>(new Set())
  const [profiles, setProfiles] = useState<ExploreProfile[]>([])
  const [metaTrades, setMetaTrades] = useState<TradeMetaRow[]>([])
  const [postSummaries, setPostSummaries] = useState<
    ReturnType<typeof buildPostSummaries>
  >({})
  const [discoverFilters, setDiscoverFilters] =
    useState<ExploreDiscoverFilters>(EXPLORE_DEFAULT_FILTERS)
  const [search, setSearch] = useState("")
  const [results, setResults] = useState<
    Pick<ExploreProfile, "id" | "username" | "name" | "avatar_url" | "is_private">[]
  >([])
  const [loadingSearch, setLoadingSearch] = useState(false)
  const [searchFinished, setSearchFinished] = useState(false)
  const [visibleCount, setVisibleCount] = useState(EXPLORE_PAGE_SIZE)
  const [loadingMore, setLoadingMore] = useState(false)
  const [hasMoreProfiles, setHasMoreProfiles] = useState(true)

  useEffect(() => {
    setVisibleCount(EXPLORE_PAGE_SIZE)
  }, [
    discoverFilters.category,
    discoverFilters.session,
    discoverFilters.experience,
    discoverFilters.tradingStyle,
    discoverFilters.market,
  ])

  useEffect(() => {
    if (defaultCategorySet.current || !viewerProfile?.trader_type) return
    defaultCategorySet.current = true
    setDiscoverFilters((prev) => ({
      ...prev,
      category: categoryTabFromTraderType(viewerProfile.trader_type),
    }))
  }, [viewerProfile?.trader_type])

  async function loadTradeMetaRows() {
    if (isDemoModeActive()) {
      setMetaTrades(getDemoExploreTradeMetaRows())
      return
    }

    const { data, error } = await supabase
      .from("trades")
      .select("user_id, session, ticker, created_at, pnl")
      .eq("is_public", true)
      .order("created_at", { ascending: false })
      .limit(EXPLORE_TRADE_ROW_LIMIT)

    if (error) {
      console.error("[explore] trade meta fetch error:", error)
      return
    }

    setMetaTrades((data || []) as TradeMetaRow[])
  }

  async function fetchProfileBatch(
    offset: number,
    limit = EXPLORE_PAGE_SIZE
  ): Promise<{ added: ExploreProfile[]; hasMore: boolean }> {
    if (isDemoModeActive()) {
      return { added: [], hasMore: false }
    }

    const { data, error } = await supabase
      .from("profiles")
      .select(PROFILE_FIELDS)
      .not("username", "is", null)
      .neq("is_private", true)
      .order("created_at", { ascending: false })
      .range(offset, offset + limit - 1)

    if (error) {
      console.error("[explore] profile batch fetch error:", error)
      return { added: [], hasMore: false }
    }

    const batch = (data as ExploreProfile[]) || []
    if (batch.length === 0) {
      return { added: [], hasMore: false }
    }

    const profileIds = batch.map((p) => p.id)
    const [socialCounts, postsRes] = await Promise.all([
      fetchExploreSocialCounts(profileIds),
      supabase
        .from("profile_posts")
        .select("user_id, created_at")
        .in("user_id", profileIds)
        .order("created_at", { ascending: false })
        .limit(500),
    ])

    const enriched = enrichExploreProfilesWithSocialCounts(batch, socialCounts)
    setPostSummaries((prev) => ({
      ...prev,
      ...buildPostSummaries(postsRes.data || []),
    }))

    return { added: enriched, hasMore: batch.length >= limit }
  }

  function restoreExploreSession(
    cached: NonNullable<ReturnType<typeof readExploreSession>>
  ) {
    setCurrentUserId(cached.currentUserId)
    setProfiles(cached.profiles)
    setFollowingIds(new Set(cached.followingIds))
    setRequestedIds(new Set(cached.requestedIds))
    setFollowsYouIds(new Set(cached.followsYouIds))
    setVisibleCount(EXPLORE_PAGE_SIZE)
    setHasMoreProfiles(
      cached.profiles.length >= EXPLORE_PAGE_SIZE && !isDemoModeActive()
    )
    initialLoadDone.current = true
    setLoading(false)
    if (cached.scrollY > 0) {
      requestAnimationFrame(() => window.scrollTo(0, cached.scrollY))
    }
    void loadTradeMetaRows()
  }

  useEffect(() => {
    if (isDemoModeActive() && !user?.id) return
    const cached = readExploreSession()
    if (cached) {
      restoreExploreSession(cached)
      return
    }
    void init()
  }, [user?.id])

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

      if (isDemoModeActive()) {
        setResults(searchDemoExploreProfiles(term))
        setLoadingSearch(false)
        setSearchFinished(true)
        return
      }

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

    if (isDemoModeActive()) {
      const uid = user?.id ?? null
      const demoProfiles = getDemoExploreProfiles()
      const followingIdsArr = getDemoExploreFollowingIds(uid)
      const followsYouIdsArr = getDemoExploreFollowsYouIds(uid)

      setCurrentUserId(uid)
      setProfiles(demoProfiles)
      setFollowingIds(new Set(followingIdsArr))
      setRequestedIds(new Set())
      setFollowsYouIds(new Set(followsYouIdsArr))
      setMetaTrades(getDemoExploreTradeMetaRows())
      setPostSummaries({})
      setHasMoreProfiles(false)

      writeExploreSession({
        currentUserId: uid,
        profiles: demoProfiles,
        followingIds: followingIdsArr,
        requestedIds: [],
        followsYouIds: followsYouIdsArr,
        tradesByView: {},
        topView: "30D",
        scrollY: 0,
      })

      initialLoadDone.current = true
      setLoading(false)
      return
    }

    setCurrentUserId(user?.id ?? null)

    const [followingRes, requestsRes, followsYouRes] = await Promise.all([
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

    const { added, hasMore } = await fetchProfileBatch(0, EXPLORE_PAGE_SIZE)
    setProfiles(added)
    setHasMoreProfiles(hasMore)

    await loadTradeMetaRows()

    setFollowingIds(
      new Set((followingRes.data || []).map((row) => String(row.following_id)))
    )
    setRequestedIds(
      new Set((requestsRes.data || []).map((row) => String(row.target_id)))
    )
    setFollowsYouIds(
      new Set((followsYouRes.data || []).map((row) => String(row.follower_id)))
    )

    writeExploreSession({
      currentUserId: user?.id ?? null,
      profiles: added,
      followingIds: (followingRes.data || []).map((row) =>
        String(row.following_id)
      ),
      requestedIds: (requestsRes.data || []).map((row) =>
        String(row.target_id)
      ),
      followsYouIds: (followsYouRes.data || []).map((row) =>
        String(row.follower_id)
      ),
      tradesByView: {},
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

  const tradeMetaByUserId = useMemo(
    () => buildTraderTradeMeta(metaTrades),
    [metaTrades]
  )

  const tradeSummaries = useMemo(
    () => buildTradeSummaries(metaTrades),
    [metaTrades]
  )

  const filterAvailability = useMemo(
    () =>
      discoverFilterAvailability({
        profiles,
        tradeMetaByUserId,
      }),
    [profiles, tradeMetaByUserId]
  )

  const excludeSelf = useMemo(() => {
    const ids = new Set<string>()
    if (currentUserId) ids.add(currentUserId)
    return ids
  }, [currentUserId])

  const displayedTraders = useMemo(() => {
    const ranked = rankExploreDiscoverList(
      profiles,
      tradeSummaries,
      postSummaries,
      { excludeUserIds: excludeSelf }
    )
    return filterExploreProfiles(ranked, discoverFilters, tradeMetaByUserId)
  }, [
    profiles,
    tradeSummaries,
    postSummaries,
    excludeSelf,
    discoverFilters,
    tradeMetaByUserId,
  ])

  const visibleTraders = useMemo(
    () => displayedTraders.slice(0, visibleCount),
    [displayedTraders, visibleCount]
  )

  const showLoadMore =
    visibleCount < displayedTraders.length || hasMoreProfiles

  async function handleLoadMore() {
    if (loadingMore) return
    setLoadingMore(true)

    try {
      if (visibleCount < displayedTraders.length) {
        setVisibleCount((count) => count + EXPLORE_PAGE_SIZE)
        return
      }

      if (!hasMoreProfiles || isDemoModeActive()) {
        return
      }

      const { added, hasMore } = await fetchProfileBatch(profiles.length)
      if (added.length > 0) {
        setProfiles((prev) => {
          const merged = mergeExploreProfiles(prev, added)
          const cached = readExploreSession()
          if (cached) {
            writeExploreSession({ ...cached, profiles: merged })
          }
          return merged
        })
      }
      setHasMoreProfiles(hasMore)
      setVisibleCount((count) => count + EXPLORE_PAGE_SIZE)
    } finally {
      setLoadingMore(false)
    }
  }

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
    <div className="w-full px-2 pb-3 pt-0 text-white md:px-4 md:pb-10">
      <div className="relative z-0 mx-auto mt-2.5 flex w-full max-w-7xl flex-col gap-3 px-1 md:gap-4 md:px-6">
        <header>
          <p className="text-xs font-semibold uppercase tracking-wide text-blue-300">
            Discover
          </p>
          <h1 className="mt-0.5 text-2xl font-semibold text-blue-300 md:text-3xl">
            Explore
          </h1>
          <p className="mt-1 text-sm text-gray-400">
            Find traders to follow by market, style, and session.
          </p>
        </header>

        <section className={`${PANEL_CLASS} relative z-20`}>
          <label htmlFor="explore-search" className="sr-only">
            Search traders
          </label>
          <input
            id="explore-search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search by username or display name…"
            className={SEARCH_INPUT_CLASS}
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

          {searchFinished &&
          search.trim().length >= SEARCH_MIN_CHARS &&
          results.length === 0 ? (
            <div className="mt-3">
              <EmptyState
                title="No traders found"
                description={`No profiles match "${search.trim()}".`}
                className="py-6"
              />
            </div>
          ) : null}

          {results.length > 0 ? (
            <div className="absolute left-0 right-0 z-[100] mt-2 overflow-hidden rounded-xl border border-white/10 bg-[#0f172a] shadow-xl">
              {results.map((result) => (
                <div
                  key={result.id}
                  className="flex items-center justify-between gap-3 border-b border-white/5 px-3 py-2.5 last:border-b-0 hover:bg-white/5"
                >
                  <Link
                    href={profilePath({
                      id: result.id,
                      username: result.username,
                    })}
                    className="flex min-w-0 items-center gap-3"
                  >
                    <ProfileAvatarImg
                      src={result.avatar_url}
                      className="h-10 w-10 shrink-0 border border-white/10"
                    />
                    <div className="min-w-0">
                      <p className="truncate font-medium text-gray-100">
                        {result.name?.trim() || result.username}
                      </p>
                      {result.username ? (
                        <p className="truncate text-xs text-gray-400">
                          @{result.username}
                        </p>
                      ) : null}
                    </div>
                  </Link>
                  <FollowButton
                    targetUserId={result.id}
                    currentUserId={currentUserId}
                    targetIsPrivate={result.is_private}
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
        </section>

        {!loading ? (
          <section className={PANEL_CLASS}>
            <ExploreDiscoverBar
              filters={discoverFilters}
              onChange={(patch) =>
                setDiscoverFilters((prev) => ({ ...prev, ...patch }))
              }
              availability={filterAvailability}
            />
          </section>
        ) : null}

        {loading ? (
          <SkeletonExplorePage />
        ) : displayedTraders.length === 0 ? (
          <EmptyState
            title="No traders match these filters"
            description="Try a broader category or clear your filters."
            className="py-12"
          />
        ) : (
          <section className={PANEL_CLASS}>
            <p className="mb-3 text-xs text-gray-400">
              Showing {visibleTraders.length.toLocaleString()} of{" "}
              {displayedTraders.length.toLocaleString()} trader
              {displayedTraders.length === 1 ? "" : "s"}
              {hasMoreProfiles ? "+" : ""}
            </p>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {visibleTraders.map((profile, index) => (
                <ExploreTraderCard
                  key={profile.id}
                  profile={profile}
                  tradeMeta={tradeMetaByUserId[profile.id]}
                  currentUserId={currentUserId}
                  followingIds={followingIds}
                  requestedIds={requestedIds}
                  followsYouIds={followsYouIds}
                  onFollowingChange={handleFollowingChange}
                  onRequestedChange={handleRequestedChange}
                  eagerAvatar={index < 6}
                />
              ))}
            </div>
            {showLoadMore ? (
              <div className="mt-4 flex justify-center">
                <button
                  type="button"
                  onClick={() => void handleLoadMore()}
                  disabled={loadingMore}
                  className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
                >
                  {loadingMore ? "Loading…" : "Load More"}
                </button>
              </div>
            ) : null}
          </section>
        )}
      </div>
    </div>
  )
}
