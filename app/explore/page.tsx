"use client"

import Link from "next/link"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import FollowButton from "../components/FollowButton"
import ExploreDiscoverBar from "../components/explore/ExploreDiscoverBar"
import ExploreTraderCard from "../components/explore/ExploreTraderCard"
import EmptyState from "../components/ui/EmptyState"
import { SkeletonExplorePage, SkeletonTraderCard } from "../components/ui/skeletons"
import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import {
  buildPostSummaries,
  enrichExploreProfilesWithSocialCounts,
  fetchExploreSocialCounts,
  fetchExploreTradeMetaAggregates,
  mergeExploreProfiles,
  rankExploreDiscoverList,
  type ExploreProfile,
  type ExploreTradeMetaPayload,
} from "@/lib/exploreDiscover"
import {
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
  searchDemoExploreProfiles,
} from "@/lib/demo/demoExplore"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { scheduleDeferredWork } from "@/lib/scheduleDeferredWork"

const EXPLORE_PAGE_SIZE = 16

const PROFILE_FIELDS =
  "id, username, name, avatar_url, bio, created_at, is_private, trader_type, trading_style, trading_model, primary_market, started_trading" as const

const SEARCH_PROFILE_FIELDS =
  "id, username, name, avatar_url, is_private" as const

const SEARCH_MIN_CHARS = 2

const PANEL_CLASS =
  "rounded-xl border border-white/10 bg-white/5 p-2.5 backdrop-blur-md md:p-3"

const SEARCH_INPUT_CLASS =
  "min-w-0 flex-1 rounded-xl border border-white/15 bg-black/40 p-3 text-sm text-white placeholder:text-gray-400 focus:border-blue-400/50 focus:outline-none focus:ring-2 focus:ring-blue-500/40"

const FILTER_TOGGLE_CLASS =
  "inline-flex shrink-0 items-center justify-center gap-2 rounded-xl border border-white/15 bg-white/5 px-3 py-3 text-sm font-medium text-white transition hover:bg-white/10"

const EMPTY_TRADE_META: ExploreTradeMetaPayload = {
  tradeSummaries: {},
  tradeMetaByUserId: {},
}

export default function ExplorePage() {
  const { user } = useUserProfile()
  const initialLoadDone = useRef(false)
  const [loading, setLoading] = useState(true)
  const [currentUserId, setCurrentUserId] = useState<string | null>(null)
  const [followingIds, setFollowingIds] = useState<Set<string>>(new Set())
  const [requestedIds, setRequestedIds] = useState<Set<string>>(new Set())
  const [followsYouIds, setFollowsYouIds] = useState<Set<string>>(new Set())
  const [profiles, setProfiles] = useState<ExploreProfile[]>([])
  const [tradeMetaPayload, setTradeMetaPayload] =
    useState<ExploreTradeMetaPayload>(EMPTY_TRADE_META)
  const [postSummaries, setPostSummaries] = useState<
    ReturnType<typeof buildPostSummaries>
  >({})
  const [discoverFilters, setDiscoverFilters] =
    useState<ExploreDiscoverFilters>(EXPLORE_DEFAULT_FILTERS)
  const [draftFilters, setDraftFilters] =
    useState<ExploreDiscoverFilters>(EXPLORE_DEFAULT_FILTERS)
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [search, setSearch] = useState("")
  const [results, setResults] = useState<
    Pick<ExploreProfile, "id" | "username" | "name" | "avatar_url" | "is_private">[]
  >([])
  const [loadingSearch, setLoadingSearch] = useState(false)
  const [searchFinished, setSearchFinished] = useState(false)
  const [visibleCount, setVisibleCount] = useState(EXPLORE_PAGE_SIZE)
  const [loadingMore, setLoadingMore] = useState(false)
  const [hasMoreProfiles, setHasMoreProfiles] = useState(true)
  const [exploreLoadError, setExploreLoadError] = useState<string | null>(null)
  const [exploreSearchError, setExploreSearchError] = useState<string | null>(
    null
  )

  useEffect(() => {
    setVisibleCount(EXPLORE_PAGE_SIZE)
  }, [
    discoverFilters.category,
    discoverFilters.session,
    discoverFilters.experience,
    discoverFilters.tradingStyle,
    discoverFilters.market,
  ])

  function toggleFiltersPanel() {
    if (filtersOpen) {
      setFiltersOpen(false)
      return
    }
    setDraftFilters(discoverFilters)
    setFiltersOpen(true)
  }

  function applyDiscoverFilters() {
    setDiscoverFilters(draftFilters)
    setFiltersOpen(false)
  }

  async function loadTradeMetaRows() {
    const payload = await fetchExploreTradeMetaAggregates()
    setTradeMetaPayload(payload)
  }

  async function fetchProfileBatch(
    offset: number,
    limit = EXPLORE_PAGE_SIZE
  ): Promise<{ added: ExploreProfile[]; hasMore: boolean; error: boolean }> {
    if (isDemoModeActive()) {
      return { added: [], hasMore: false, error: false }
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
      return { added: [], hasMore: false, error: true as const }
    }

    const batch = (data as ExploreProfile[]) || []
    if (batch.length === 0) {
      return { added: [], hasMore: false, error: false as const }
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

    return { added: enriched, hasMore: batch.length >= limit, error: false }
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
    scheduleDeferredWork(() => {
      void loadTradeMetaRows()
    }, 1000)
  }

  useEffect(() => {
    if (isDemoModeActive() && !user?.id) return
    const cached = readExploreSession(user?.id ?? null)
    if (cached) {
      restoreExploreSession(cached)
      return
    }
    void init()
  }, [user?.id])

  const runExploreSearch = useCallback(async (term: string) => {
    setLoadingSearch(true)
    setSearchFinished(false)

    if (isDemoModeActive()) {
      setResults(searchDemoExploreProfiles(term))
      setLoadingSearch(false)
      setSearchFinished(true)
      setExploreSearchError(null)
      return
    }

    const { data, error } = await supabase
      .from("profiles")
      .select(SEARCH_PROFILE_FIELDS)
      .or(`username.ilike.%${term}%,name.ilike.%${term}%`)
      .not("username", "is", null)
      .neq("is_private", true)
      .limit(8)

    if (error) {
      console.error("[explore] search error:", error)
      setResults([])
      setExploreSearchError("Couldn't search traders. Please try again.")
      setLoadingSearch(false)
      setSearchFinished(true)
      return
    }

    setResults(data || [])
    setExploreSearchError(null)
    setLoadingSearch(false)
    setSearchFinished(true)
  }, [])

  useEffect(() => {
    const term = search.trim()
    if (term.length < SEARCH_MIN_CHARS) {
      setResults([])
      setLoadingSearch(false)
      setSearchFinished(false)
      setExploreSearchError(null)
      return
    }

    const delayDebounce = setTimeout(() => {
      void runExploreSearch(term)
    }, 300)

    return () => clearTimeout(delayDebounce)
  }, [search, runExploreSearch])

  async function init() {
    setLoading(true)
    setExploreLoadError(null)

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
      setTradeMetaPayload(await fetchExploreTradeMetaAggregates())
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

    const [
      [followingRes, requestsRes, followsYouRes],
      { added, hasMore, error: profilesError },
    ] = await Promise.all([
      Promise.all([
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
      ]),
      fetchProfileBatch(0, EXPLORE_PAGE_SIZE),
    ])
    if (profilesError) {
      setProfiles([])
      setHasMoreProfiles(false)
      setExploreLoadError("Couldn't load traders. Please try again.")
      initialLoadDone.current = true
      setLoading(false)
      return
    }
    setProfiles(added)
    setHasMoreProfiles(hasMore)
    setExploreLoadError(null)

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
    scheduleDeferredWork(() => {
      void loadTradeMetaRows()
    }, 1000)
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

  const tradeMetaByUserId = tradeMetaPayload.tradeMetaByUserId
  const tradeSummaries = tradeMetaPayload.tradeSummaries

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
        <header className="hidden md:block">
          <h1 className="text-lg font-semibold text-white md:text-xl">
            Explore
          </h1>
        </header>

        <section className={`${PANEL_CLASS} relative z-20`}>
          <div className="flex items-stretch gap-2">
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
            <button
              type="button"
              onClick={toggleFiltersPanel}
              aria-expanded={filtersOpen}
              aria-controls="explore-filters-panel"
              aria-label="Filter"
              className={FILTER_TOGGLE_CLASS}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.75"
                strokeLinecap="round"
                strokeLinejoin="round"
                className="h-5 w-5 shrink-0"
                aria-hidden
              >
                <polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3" />
              </svg>
              <span className="hidden md:inline">Filter</span>
            </button>
          </div>

          {search.trim().length > 0 &&
          search.trim().length < SEARCH_MIN_CHARS ? (
            <p className="mt-2 text-xs text-gray-400">
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
                title={
                  exploreSearchError
                    ? "Couldn't Search Traders"
                    : "No traders found"
                }
                description={
                  exploreSearchError ??
                  `No profiles match "${search.trim()}".`
                }
                className="py-6"
                action={
                  exploreSearchError ? (
                    <button
                      type="button"
                      onClick={() => void runExploreSearch(search.trim())}
                      className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
                    >
                      Retry
                    </button>
                  ) : undefined
                }
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
                      <p className="truncate font-semibold text-white">
                        {result.name?.trim() || result.username}
                      </p>
                      {result.username ? (
                        <p className="truncate text-xs text-gray-300">
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

        {filtersOpen && !loading ? (
          <section
            id="explore-filters-panel"
            className={PANEL_CLASS}
          >
            <ExploreDiscoverBar
              filters={draftFilters}
              onChange={(patch) =>
                setDraftFilters((prev) => ({ ...prev, ...patch }))
              }
              availability={filterAvailability}
            />
            <div className="mt-3.5 flex justify-end border-t border-white/10 pt-3">
              <button
                type="button"
                onClick={applyDiscoverFilters}
                className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
              >
                Apply Filters
              </button>
            </div>
          </section>
        ) : null}

        {loading ? (
          <SkeletonExplorePage />
        ) : exploreLoadError ? (
          <EmptyState
            title="Couldn't Load Traders"
            description={exploreLoadError}
            className="py-12"
            action={
              <button
                type="button"
                onClick={() => void init()}
                className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
              >
                Retry
              </button>
            }
          />
        ) : displayedTraders.length === 0 ? (
          <EmptyState
            title="No traders match these filters"
            description="Try a broader category or clear your filters."
            className="py-12"
          />
        ) : (
          <section className={PANEL_CLASS}>
            <p className="mb-3 text-xs text-gray-300">
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
