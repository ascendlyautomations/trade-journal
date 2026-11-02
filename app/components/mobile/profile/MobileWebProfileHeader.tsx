"use client"

import type { ChangeEvent, RefObject } from "react"
import FollowButton from "@/app/components/FollowButton"
import StoryAvatarRing from "@/app/components/feed/StoryAvatarRing"
import ProfileCreateMenu from "@/app/components/profile/ProfileCreateMenu"
import ProfileVisitorModerationMenu from "@/app/components/profile/ProfileVisitorModerationMenu"
import type { ProfileHeaderData } from "@/app/components/profile/profileTypes"
import { normalizeTraderType } from "@/lib/traderType"
import { ChevronRight, Share, TrendingUp } from "lucide-react"
import MobileWebProfileStatsRow from "./MobileWebProfileStatsRow"

type MobileWebProfileHeaderProps = {
  profile: ProfileHeaderData
  currentUserId: string | null
  storyTriggerRef: RefObject<HTMLDivElement | null>
  hasActiveStory: boolean
  followersCount: number
  followingCount: number
  metaLoading: boolean
  followingIds: Set<string>
  requestedIds: Set<string>
  followsYouIds: Set<string>
  messageBusy: boolean
  hasRoom: boolean
  canShowVisitorRoomCta: boolean
  onStoryFileSelect: (event: ChangeEvent<HTMLInputElement>) => void
  onOpenStory: () => void
  onFollowingChange: (targetUserId: string, following: boolean) => void
  onRequestedChange: (targetUserId: string, requested: boolean) => void
  onMessage: () => void
  onOpenFollowers: () => void
  onOpenFollowing: () => void
  onEditProfile: () => void
  onCreateStory: () => void
  onCreatePost: () => void
  onCreateReel: () => void
  onCreateQuickTrade: () => void
  onCreateRoom: () => void
  onViewRoom: () => void
  overviewVisible: boolean
  overviewIsPrivate: boolean
  overviewTotalTrades: number
  overviewPostsCount: number | null
  overviewWinRate: number
  overviewPayoutTotal: number | null
  overviewProfitFactor: number | null
}

function getExperience(startDate: string | null | undefined) {
  if (!startDate) return ""
  const start = new Date(startDate)
  if (Number.isNaN(start.getTime())) return ""
  const now = new Date()
  const months =
    (now.getFullYear() - start.getFullYear()) * 12 +
    (now.getMonth() - start.getMonth())
  const years = Math.floor(months / 12)
  const remainingMonths = months % 12
  return `${years}y ${remainingMonths}m`
}

function formatUsernameHandle(username: string) {
  const trimmed = username.trim()
  if (!trimmed) return ""
  return trimmed.startsWith("@") ? trimmed : `@${trimmed}`
}

function formatProfileMetadataLine(profile: ProfileHeaderData) {
  const parts: string[] = [
    profile.trading_style?.trim() || profile.trading_model?.trim() || "—",
  ]
  const traderType = normalizeTraderType(profile.trader_type)
  if (traderType) parts.push(traderType)
  const market = profile.primary_market?.trim()
  if (market) parts.push(market)
  parts.push(getExperience(profile.started_trading) || "N/A")
  return parts.join(" · ")
}

function compactCount(value: number): string {
  if (!Number.isFinite(value)) return "0"
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`
  if (value >= 10_000) return `${Math.round(value / 1000)}K`
  if (value >= 1000) return `${(value / 1000).toFixed(1)}K`
  return String(value)
}

async function shareProfile(profile: ProfileHeaderData) {
  const username = String(profile.username ?? "").trim()
  const path = username
    ? `/profile/${encodeURIComponent(username)}`
    : `/profile/${encodeURIComponent(String(profile.id ?? ""))}`
  const url = `${window.location.origin}${path}`
  const title = profile.name || username || "TradeTraxs profile"
  try {
    if (navigator.share) {
      await navigator.share({ title, url })
      return
    }
  } catch {
    return
  }
  try {
    await navigator.clipboard.writeText(url)
  } catch {
    /* ignore */
  }
}

const CHIP_OUTLINE =
  "inline-flex h-8 min-h-11 flex-1 items-center justify-center gap-1 rounded-[14px] border border-border bg-transparent px-2.5 text-[13px] font-semibold text-[color:var(--tt-text,#1f2328)]"

export default function MobileWebProfileHeader({
  profile,
  currentUserId,
  hasActiveStory,
  followersCount,
  followingCount,
  metaLoading,
  followingIds,
  requestedIds,
  followsYouIds,
  messageBusy,
  hasRoom,
  canShowVisitorRoomCta,
  onOpenStory,
  onFollowingChange,
  onRequestedChange,
  onMessage,
  onOpenFollowers,
  onOpenFollowing,
  onEditProfile,
  onCreateStory,
  onCreatePost,
  onCreateReel,
  onCreateQuickTrade,
  onCreateRoom,
  onViewRoom,
  overviewVisible,
  overviewIsPrivate,
  overviewTotalTrades,
  overviewPostsCount,
  overviewWinRate,
  overviewPayoutTotal,
  overviewProfitFactor,
}: MobileWebProfileHeaderProps) {
  const isOwnProfile = currentUserId === profile.id
  const followsYou = followsYouIds.has(profile.id)
  const bio = profile.bio?.trim() ?? ""
  const showRoomRow = isOwnProfile || canShowVisitorRoomCta

  return (
    <div
      className="relative px-1 pt-1"
      {...(isOwnProfile ? { "data-tt-tour-target": "profileIdentity" } : {})}
    >
      {isOwnProfile ? (
        <div className="absolute right-0 top-0 z-10">
          <ProfileCreateMenu
            onCreateStory={onCreateStory}
            onCreatePost={onCreatePost}
            onCreateReel={onCreateReel}
            onCreateQuickTrade={onCreateQuickTrade}
          />
        </div>
      ) : currentUserId ? (
        <div className="absolute right-0 top-0 z-10">
          <ProfileVisitorModerationMenu
            profileId={profile.id}
            displayName={profile.name || profile.username}
            viewerUserId={currentUserId}
          />
        </div>
      ) : null}

      <div className="flex items-center gap-3">
        {hasActiveStory ? (
          <button
            type="button"
            onClick={onOpenStory}
            className="shrink-0 rounded-full outline-none focus-visible:ring-2 focus-visible:ring-[#4EC4E0]/60"
            aria-label={`View ${profile.username || "user"}'s story`}
          >
            <StoryAvatarRing
              profile={profile}
              hasActiveStory
              priority
              displaySizePx={88}
              sizeClassName="h-[88px] w-[88px]"
            />
          </button>
        ) : (
          <StoryAvatarRing
            profile={profile}
            hasActiveStory={false}
            priority
            displaySizePx={88}
            sizeClassName="h-[88px] w-[88px]"
          />
        )}

        <div className="min-w-0 flex-1 pr-10">
          <h1 className="text-[1.1875rem] font-semibold leading-tight tracking-tight text-[color:var(--tt-text,#1f2328)]">
            {profile.name || profile.username || "User"}
          </h1>
          {profile.username ? (
            <p className="truncate text-[14px] text-[color:var(--tt-text-muted,#57606a)]">
              {formatUsernameHandle(profile.username)}
            </p>
          ) : null}
          {followsYou && !isOwnProfile ? (
            <p className="text-[11px] font-medium text-[color:var(--tt-text-muted,#57606a)]">
              Follows you
            </p>
          ) : null}
          <p className="mt-0.5 line-clamp-2 text-[13px] text-[color:var(--tt-text-muted,#57606a)]">
            {formatProfileMetadataLine(profile)}
          </p>
          <p className="mt-1 flex flex-wrap items-center gap-1 text-[13px] font-medium text-[color:var(--tt-text,#1f2328)]">
            <button
              type="button"
              onClick={onOpenFollowers}
              className="min-h-11 tabular-nums"
            >
              {metaLoading ? "—" : compactCount(followersCount)} Followers
            </button>
            <span aria-hidden className="text-[color:var(--tt-text-muted,#57606a)]">
              •
            </span>
            <button
              type="button"
              onClick={onOpenFollowing}
              className="min-h-11 tabular-nums"
            >
              {metaLoading ? "—" : compactCount(followingCount)} Following
            </button>
          </p>
        </div>
      </div>

      <MobileWebProfileStatsRow
        visible={overviewVisible}
        isPrivate={overviewIsPrivate}
        totalTrades={overviewTotalTrades}
        postsCount={overviewPostsCount}
        winRate={overviewWinRate}
        payoutTotal={overviewPayoutTotal}
        profitFactor={overviewProfitFactor}
      />

      {bio ? (
        <p className="mt-1 whitespace-pre-wrap break-words text-[14px] leading-relaxed text-[color:var(--tt-text,#1f2328)]">
          {bio}
        </p>
      ) : null}

      <div className="mt-2 flex items-center gap-2">
        {isOwnProfile ? (
          <>
            <button type="button" onClick={onEditProfile} className={CHIP_OUTLINE}>
              Edit Profile
            </button>
            <button
              type="button"
              onClick={() => void shareProfile(profile)}
              className={CHIP_OUTLINE}
            >
              <Share className="h-3.5 w-3.5" strokeWidth={2.25} aria-hidden />
              Share
            </button>
          </>
        ) : currentUserId ? (
          <>
            <div className="min-w-0 flex-1">
              <FollowButton
                targetUserId={profile.id}
                currentUserId={currentUserId}
                targetIsPrivate={profile.is_private}
                followingIds={followingIds}
                requestedIds={requestedIds}
                followsYouIds={followsYouIds}
                onFollowingChange={onFollowingChange}
                onRequestedChange={onRequestedChange}
                stopPropagation={false}
                className="!h-8 !min-h-11 !w-full !rounded-[14px] !px-2.5 !text-[13px]"
              />
            </div>
            <button
              type="button"
              onClick={onMessage}
              disabled={messageBusy}
              className={`${CHIP_OUTLINE} disabled:opacity-50`}
            >
              {messageBusy ? "Opening…" : "Message"}
            </button>
          </>
        ) : null}
      </div>

      {showRoomRow ? (
        <button
          type="button"
          onClick={isOwnProfile ? (hasRoom ? onViewRoom : onCreateRoom) : onViewRoom}
          data-tt-tour-target="profileTradeRoom"
          className="mt-2 flex min-h-11 w-full items-center gap-2 rounded-[18px] border border-border bg-surface-elevated px-3 py-2 text-left"
        >
          <TrendingUp className="h-4 w-4 shrink-0 text-info" strokeWidth={2.25} aria-hidden />
          <span className="min-w-0 flex-1 text-[15px] text-[color:var(--tt-text,#1f2328)]">
            {isOwnProfile
              ? hasRoom
                ? "View Trade Room"
                : "Create Trade Room"
              : "View Trade Room"}
          </span>
          <ChevronRight className="h-4 w-4 shrink-0 text-[color:var(--tt-text-muted,#57606a)]" aria-hidden />
        </button>
      ) : null}
    </div>
  )
}
