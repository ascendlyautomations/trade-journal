"use client"

import Link from "next/link"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import FollowButton from "@/app/components/FollowButton"
import {
  type ExploreProfile,
  type TraderTradeMeta,
} from "@/lib/exploreDiscover"
import { profilePath } from "@/lib/profileRoutes"
import { normalizeTraderType } from "@/lib/traderType"

type ExploreTraderCardProps = {
  profile: ExploreProfile
  tradeMeta?: TraderTradeMeta
  currentUserId: string | null
  followingIds: Set<string>
  requestedIds: Set<string>
  followsYouIds: Set<string>
  onFollowingChange: (userId: string, following: boolean) => void
  onRequestedChange: (userId: string, requested: boolean) => void
  eagerAvatar?: boolean
}

export default function ExploreTraderCard({
  profile,
  tradeMeta,
  currentUserId,
  followingIds,
  requestedIds,
  followsYouIds,
  onFollowingChange,
  onRequestedChange,
  eagerAvatar = false,
}: ExploreTraderCardProps) {
  const displayName =
    profile.name?.trim() || profile.username?.trim() || "Trader"
  const username = profile.username?.trim()
  const href = profilePath({ id: profile.id, username: profile.username })
  const traderType = normalizeTraderType(profile.trader_type)
  const whatTheyTrade = traderType
    ? traderType === "Investor"
      ? "Investing"
      : traderType
    : null
  const tradingStyle =
    profile.trading_style?.trim() || profile.trading_model?.trim() || null
  const session = tradeMeta?.dominantSession
    ? tradeMeta.dominantSession === "NY"
      ? "NY Session"
      : tradeMeta.dominantSession
    : null

  const detailParts: string[] = []
  if (whatTheyTrade) detailParts.push(whatTheyTrade)
  if (tradingStyle) detailParts.push(tradingStyle)
  if (session) detailParts.push(session)

  const followers =
    typeof profile.followers_count === "number" && profile.followers_count > 0
      ? `${profile.followers_count.toLocaleString()} follower${
          profile.followers_count === 1 ? "" : "s"
        }`
      : null

  return (
    <article className="flex items-center gap-3 rounded-xl border border-white/10 bg-white/5 p-3 backdrop-blur-md transition hover:border-white/20 hover:bg-white/[0.08]">
      <Link href={href} className="shrink-0">
        <ProfileAvatarImg
          src={profile.avatar_url}
          className="h-11 w-11 border border-white/10"
          priority={eagerAvatar}
        />
      </Link>

      <div className="min-w-0 flex-1">
        <Link href={href} className="block min-w-0">
          <p className="truncate text-sm font-semibold text-white">
            {displayName}
          </p>
          {username ? (
            <p className="truncate text-xs text-gray-300">@{username}</p>
          ) : null}
        </Link>
        {detailParts.length > 0 ? (
          <p className="mt-1 truncate text-xs text-gray-300">
            {detailParts.join(" · ")}
          </p>
        ) : null}
        {followers ? (
          <p className="mt-0.5 truncate text-xs text-gray-400">{followers}</p>
        ) : null}
      </div>

      <div className="shrink-0">
        <FollowButton
          targetUserId={profile.id}
          currentUserId={currentUserId}
          targetIsPrivate={profile.is_private}
          followingIds={followingIds}
          requestedIds={requestedIds}
          followsYouIds={followsYouIds}
          onFollowingChange={onFollowingChange}
          onRequestedChange={onRequestedChange}
        />
      </div>
    </article>
  )
}
