"use client"

import Link from "next/link"
import FollowButton from "@/app/components/FollowButton"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import type { ExploreProfile } from "@/lib/exploreDiscover"
import { countNoun } from "@/lib/countNoun"
import { profilePath } from "@/lib/profileRoutes"
import { Trophy } from "lucide-react"
import ExploreLiveTradersNowSection from "@/app/components/explore/ExploreLiveTradersNowSection"
import type { ExploreLiveTraderNow } from "@/lib/exploreLiveTradersNowClient"

type MobileWebExploreDiscoveryProps = {
  traders: ExploreProfile[]
  currentUserId: string | null
  followingIds: Set<string>
  requestedIds: Set<string>
  followsYouIds: Set<string>
  onFollowingChange: (userId: string, following: boolean) => void
  onRequestedChange: (userId: string, requested: boolean) => void
  onLoadMore?: () => void
  loadingMore?: boolean
  showLoadMore?: boolean
  liveTraders?: ExploreLiveTraderNow[]
  liveTradersLoading?: boolean
  liveTradersError?: string | null
  onRetryLiveTraders?: () => void
}

export default function MobileWebExploreDiscovery({
  traders,
  currentUserId,
  followingIds,
  requestedIds,
  followsYouIds,
  onFollowingChange,
  onRequestedChange,
  onLoadMore,
  loadingMore = false,
  showLoadMore = false,
  liveTraders = [],
  liveTradersLoading = false,
  liveTradersError = null,
  onRetryLiveTraders,
}: MobileWebExploreDiscoveryProps) {
  return (
    <div className="flex flex-col gap-5">
      <Link
        href="/leaderboard"
        className="flex min-h-[72px] items-center gap-3 rounded-[10px] border border-[color:color-mix(in_srgb,var(--tt-text)_12%,transparent)] bg-[color:var(--tt-surface-nested,#1a222c)] px-3 py-2.5"
      >
        <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-[color:color-mix(in_srgb,var(--tt-accent)_18%,transparent)] text-[color:var(--tt-accent,#4ec4e0)]">
          <Trophy className="h-[18px] w-[18px]" aria-hidden />
        </span>
        <span className="min-w-0 flex-1">
          <span className="block text-[15px] font-semibold text-[color:var(--tt-text,#f0f3f6)]">
            Leaderboards
          </span>
          <span className="mt-0.5 block text-[12px] text-[color:var(--tt-text-muted,#c0cad6)]">
            Rankings across the community
          </span>
        </span>
        <span className="text-[13px] text-[color:var(--tt-text-tertiary,#a8b3c2)]" aria-hidden>
          ›
        </span>
      </Link>

      <ExploreLiveTradersNowSection
        items={liveTraders}
        loading={liveTradersLoading}
        error={liveTradersError}
        onRetry={() => onRetryLiveTraders?.()}
      />

      {traders.length > 0 ? (
        <section>
          <div className="px-0.5">
            <h2 className="text-[15px] font-semibold text-[color:var(--tt-text,#f0f3f6)]">
              Suggested Traders
            </h2>
            <p className="mt-0.5 text-[12px] text-[color:var(--tt-text-tertiary,#a8b3c2)]">
              Active public profiles worth following
            </p>
          </div>
          <div className="tt-mobile-web-hscroll -mx-3 mt-3 flex gap-2.5 overflow-x-auto px-3 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            {traders.map((profile) => {
              const displayName =
                profile.name?.trim() || profile.username?.trim() || "Trader"
              const username = profile.username?.trim()
              const href = profilePath({
                id: profile.id,
                username: profile.username,
              })
              const followers =
                typeof profile.followers_count === "number" &&
                profile.followers_count > 0
                  ? countNoun(profile.followers_count, "follower")
                  : null
              return (
                <article
                  key={profile.id}
                  className="flex w-[148px] shrink-0 flex-col rounded-[10px] bg-[color:var(--tt-surface-nested,#1a222c)] p-2.5"
                >
                  <Link href={href} prefetch={false} className="min-w-0">
                    <ProfileAvatarImg
                      src={profile.avatar_url}
                      className="h-[52px] w-[52px]"
                    />
                    <p className="mt-2 truncate text-[13px] font-semibold text-[color:var(--tt-text,#f0f3f6)]">
                      {displayName}
                    </p>
                    {username ? (
                      <p className="truncate text-[11px] text-[color:var(--tt-text-muted,#c0cad6)]">
                        @{username}
                      </p>
                    ) : null}
                    {followers ? (
                      <p className="mt-1 truncate text-[11px] text-[color:var(--tt-text-tertiary,#a8b3c2)]">
                        {followers}
                      </p>
                    ) : null}
                  </Link>
                  <div className="mt-2">
                    <FollowButton
                      targetUserId={profile.id}
                      currentUserId={currentUserId}
                      targetIsPrivate={profile.is_private}
                      followingIds={followingIds}
                      requestedIds={requestedIds}
                      followsYouIds={followsYouIds}
                      onFollowingChange={onFollowingChange}
                      onRequestedChange={onRequestedChange}
                      className="tt-mobile-web-hit-y w-full justify-center px-2 text-[12px]"
                    />
                  </div>
                </article>
              )
            })}
          </div>
          {showLoadMore && onLoadMore ? (
            <div className="mt-3 flex justify-center">
              <button
                type="button"
                onClick={onLoadMore}
                disabled={loadingMore}
                className="h-11 rounded-[14px] bg-blue-500 px-4 text-sm font-semibold text-white disabled:opacity-60"
              >
                {loadingMore ? "Loading…" : "View More"}
              </button>
            </div>
          ) : null}
        </section>
      ) : null}
    </div>
  )
}
