"use client"

import type { ReactNode } from "react"
import NativeIosPullToRefresh from "@/app/components/NativeIosPullToRefresh"
import ExploreSearchResultsPanel from "@/app/components/explore/ExploreSearchResultsPanel"
import ExploreSuggestedRoomsSection from "@/app/components/explore/ExploreSuggestedRoomsSection"
import MobileWebExploreDiscovery from "./MobileWebExploreDiscovery"
import EmptyState from "@/app/components/ui/EmptyState"
import { SkeletonTraderCard } from "@/app/components/ui/skeletons"
import {
  MOBILE_WEB_EXPERIENCE_PAGE,
  MOBILE_WEB_EXPERIENCE_SEARCH,
} from "@/lib/mobileWebPageSurface"
import type { ExploreProfile } from "@/lib/exploreDiscover"
import type { ExploreLiveTraderNow } from "@/lib/exploreLiveTradersNowClient"
import type { PopularTradeRoom } from "@/lib/popularTradeRooms"
import type { ExploreSearchProfileResult } from "@/app/components/explore/ExploreSearchResultsPanel"

const SEARCH_MIN_CHARS = 2

type Props = {
  search: string
  onSearchChange: (value: string) => void
  loadingSearch: boolean
  searchFinished: boolean
  exploreSearchError: string | null
  onRetrySearch: () => void
  hasSearchResults: boolean
  searchProfiles: ExploreSearchProfileResult[]
  searchRooms: PopularTradeRoom[]
  currentUserId: string | null
  followingIds: Set<string>
  requestedIds: Set<string>
  followsYouIds: Set<string>
  memberRoomIds: Set<string>
  onFollowingChange: (userId: string, following: boolean) => void
  onRequestedChange: (userId: string, requested: boolean) => void
  onJoinSearchRoom: (room: PopularTradeRoom) => Promise<void>
  loading: boolean
  exploreLoadError: string | null
  onRetryLoad: () => void
  visibleTraders: ExploreProfile[]
  onLoadMoreTraders: () => void
  loadingMoreTraders: boolean
  showLoadMoreTraders: boolean
  liveTraders: ExploreLiveTraderNow[]
  liveTradersLoading: boolean
  liveTradersError: string | null
  onRetryLiveTraders: () => void
  onRefresh: () => void | Promise<void>
  onToggleFilters?: () => void
  filtersOpen?: boolean
  filtersSlot?: ReactNode
}

export default function MobileWebExploreHome({
  search,
  onSearchChange,
  loadingSearch,
  searchFinished,
  exploreSearchError,
  onRetrySearch,
  hasSearchResults,
  searchProfiles,
  searchRooms,
  currentUserId,
  followingIds,
  requestedIds,
  followsYouIds,
  memberRoomIds,
  onFollowingChange,
  onRequestedChange,
  onJoinSearchRoom,
  loading,
  exploreLoadError,
  onRetryLoad,
  visibleTraders,
  onLoadMoreTraders,
  loadingMoreTraders,
  showLoadMoreTraders,
  liveTraders,
  liveTradersLoading,
  liveTradersError,
  onRetryLiveTraders,
  onRefresh,
  onToggleFilters,
  filtersOpen = false,
  filtersSlot,
}: Props) {
  const trimmed = search.trim()
  const isSearching = trimmed.length >= SEARCH_MIN_CHARS

  return (
    <div className={MOBILE_WEB_EXPERIENCE_PAGE}>
      <div className="sticky top-[calc(var(--app-header-offset)+var(--app-global-upload-offset,0px))] z-10 border-b border-white/10 bg-[color:var(--tt-surface,#0d1117)] px-3 py-2">
        <div className="flex items-stretch gap-2">
          <label htmlFor="explore-search-mobile" className="sr-only">
            Search people or Trade Rooms
          </label>
          <input
            id="explore-search-mobile"
            type="search"
            inputMode="search"
            enterKeyHint="search"
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
            value={search}
            onChange={(e) => onSearchChange(e.target.value)}
            placeholder="Search people or rooms"
            className={`${MOBILE_WEB_EXPERIENCE_SEARCH} min-w-0 flex-1`}
          />
          {onToggleFilters ? (
            <button
              type="button"
              onClick={onToggleFilters}
              aria-expanded={filtersOpen}
              aria-label="Filter traders"
              className="tt-mobile-web-hit-y flex h-11 w-11 shrink-0 items-center justify-center rounded-[10px] border border-[color:color-mix(in_srgb,var(--tt-text)_12%,transparent)] bg-[color:var(--tt-surface-nested,#1a222c)] text-[color:var(--tt-text,#f0f3f6)]"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.75"
                className="h-5 w-5"
                aria-hidden
              >
                <polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3" />
              </svg>
            </button>
          ) : null}
        </div>
        {trimmed.length > 0 && trimmed.length < SEARCH_MIN_CHARS ? (
          <p className="mt-1.5 text-xs text-[color:var(--tt-text-tertiary,#a8b3c2)]">
            Type at least {SEARCH_MIN_CHARS} characters to search.
          </p>
        ) : null}
      </div>

      {filtersSlot}

      <NativeIosPullToRefresh onRefresh={onRefresh} className="min-h-0 flex-1">
        <div className="px-3 pb-[calc(var(--app-tab-bar-offset)+1rem)] pt-3">
          {isSearching ? (
            <>
              {loadingSearch ? (
                <div className="space-y-2">
                  {Array.from({ length: 4 }).map((_, i) => (
                    <SkeletonTraderCard key={i} />
                  ))}
                </div>
              ) : null}
              {searchFinished && !hasSearchResults ? (
                <EmptyState
                  title={exploreSearchError ? "Couldn't run search" : "No matches"}
                  description={
                    exploreSearchError ??
                    `Try another name, username, or Trade Room for "${trimmed}".`
                  }
                  className="py-8"
                  action={
                    exploreSearchError ? (
                      <button
                        type="button"
                        onClick={onRetrySearch}
                        className="rounded-xl bg-[color:var(--tt-accent,#4ec4e0)] px-4 py-2 text-sm font-semibold text-[#0d1117]"
                      >
                        Retry
                      </button>
                    ) : undefined
                  }
                />
              ) : null}
              {hasSearchResults ? (
                <ExploreSearchResultsPanel
                  profiles={searchProfiles}
                  rooms={searchRooms}
                  currentUserId={currentUserId}
                  followingIds={followingIds}
                  requestedIds={requestedIds}
                  followsYouIds={followsYouIds}
                  memberRoomIds={memberRoomIds}
                  onFollowingChange={onFollowingChange}
                  onRequestedChange={onRequestedChange}
                  onJoinRoom={onJoinSearchRoom}
                />
              ) : null}
            </>
          ) : loading ? (
            <div className="space-y-3">
              {Array.from({ length: 3 }).map((_, i) => (
                <SkeletonTraderCard key={i} />
              ))}
            </div>
          ) : exploreLoadError ? (
            <EmptyState
              title="Couldn't load Explore"
              description={exploreLoadError}
              className="py-12"
              action={
                <button
                  type="button"
                  onClick={onRetryLoad}
                  className="rounded-xl bg-[color:var(--tt-accent,#4ec4e0)] px-4 py-2 text-sm font-semibold text-[#0d1117]"
                >
                  Retry
                </button>
              }
            />
          ) : (
            <>
              <MobileWebExploreDiscovery
                traders={visibleTraders}
                currentUserId={currentUserId}
                followingIds={followingIds}
                requestedIds={requestedIds}
                followsYouIds={followsYouIds}
                onFollowingChange={onFollowingChange}
                onRequestedChange={onRequestedChange}
                onLoadMore={onLoadMoreTraders}
                loadingMore={loadingMoreTraders}
                showLoadMore={showLoadMoreTraders}
                liveTraders={liveTraders}
                liveTradersLoading={liveTradersLoading}
                liveTradersError={liveTradersError}
                onRetryLiveTraders={onRetryLiveTraders}
              />
              <div className="mt-5">
                <ExploreSuggestedRoomsSection memberRoomIds={memberRoomIds} />
              </div>
            </>
          )}
        </div>
      </NativeIosPullToRefresh>
    </div>
  )
}
