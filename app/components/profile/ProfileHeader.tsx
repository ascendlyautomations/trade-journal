"use client"

import type { ChangeEvent, RefObject } from "react"
import FollowButton from "@/app/components/FollowButton"
import StoryAvatarRing from "@/app/components/feed/StoryAvatarRing"
import { normalizeTraderType } from "@/lib/traderType"
import ProfileCreateMenu from "./ProfileCreateMenu"
import ProfileTradeRoomSection from "./ProfileTradeRoomSection"
import type { ProfileHeaderData } from "./profileTypes"

export type { ProfileHeaderData } from "./profileTypes"

type ProfileHeaderProps = {
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

function formatProfileMetadataLine(profile: ProfileHeaderData) {
  const parts: string[] = [
    profile.trading_style?.trim() ||
      profile.trading_model?.trim() ||
      "—",
  ]
  const traderType = normalizeTraderType(profile.trader_type)
  if (traderType) parts.push(traderType)
  const market = profile.primary_market?.trim()
  if (market) parts.push(market)
  parts.push(getExperience(profile.started_trading) || "N/A")
  return parts.join(" • ")
}

export default function ProfileHeader({
  profile,
  currentUserId,
  storyTriggerRef,
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
  onStoryFileSelect,
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
}: ProfileHeaderProps) {
  const isOwnProfile = currentUserId === profile.id

  return (
    <div className="relative bg-white/5 border border-white/10 rounded-xl p-6 backdrop-blur-md">
      {isOwnProfile ? (
        <input
          id="storyUploadInput"
          type="file"
          accept="image/*"
          className="hidden"
          onChange={onStoryFileSelect}
        />
      ) : null}
      <div className="flex flex-col items-center text-center sm:items-stretch sm:text-left md:block">
        <div className="flex w-full flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div
            ref={storyTriggerRef}
            className="flex min-w-0 w-full flex-1 flex-col items-center gap-2 sm:flex-row sm:items-center sm:gap-6"
          >
            {hasActiveStory ? (
              <button
                type="button"
                onClick={onOpenStory}
                className="shrink-0 rounded-full outline-none transition hover:opacity-90 focus-visible:ring-2 focus-visible:ring-emerald-400/60"
                aria-label={`View ${profile.username || "user"}'s story`}
              >
                <StoryAvatarRing
                  profile={profile}
                  hasActiveStory
                  priority
                  sizeClassName="h-20 w-20 md:h-24 md:w-24"
                />
              </button>
            ) : (
              <StoryAvatarRing
                profile={profile}
                hasActiveStory={false}
                priority
                sizeClassName="h-20 w-20 md:h-24 md:w-24"
              />
            )}

            <div className="flex min-w-0 w-full flex-1 flex-col justify-center text-center sm:text-left">
              <div className="flex flex-wrap items-center justify-center gap-2 sm:justify-start sm:gap-3">
                <div className="flex flex-wrap items-center justify-center gap-2 sm:justify-start">
                  <h2 className="text-lg font-semibold text-white md:text-xl">
                    {profile.name || profile.username || "User"}
                  </h2>

                  {profile.username ? (
                    <>
                      <span className="text-gray-400">|</span>
                      <span className="text-sm text-gray-400">
                        {profile.username}
                      </span>
                    </>
                  ) : null}

                  {isOwnProfile ? (
                    <div className="hidden items-center gap-2 sm:flex">
                      <button
                        type="button"
                        onClick={onEditProfile}
                        className="rounded-md bg-gray-600 px-2 py-1 text-xs text-gray-100 hover:bg-gray-500 md:bg-white/10 md:px-2 md:py-0.5 md:text-xs md:hover:bg-white/20"
                      >
                        Edit Profile
                      </button>
                    </div>
                  ) : null}
                </div>

                {currentUserId && !isOwnProfile ? (
                  <div className="flex w-full flex-wrap items-center justify-center gap-2 sm:w-auto sm:justify-start">
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
                    />

                    <button
                      type="button"
                      onClick={onMessage}
                      disabled={messageBusy}
                      className="rounded-md border border-white/10 bg-white/10 px-3 py-1 text-sm text-gray-100 hover:bg-white/20 disabled:opacity-50"
                    >
                      Message
                    </button>
                  </div>
                ) : null}
              </div>

              <p className="mt-1 flex flex-wrap items-center justify-center gap-1 text-sm text-gray-400 sm:justify-start">
                <span
                  role="button"
                  tabIndex={0}
                  onClick={onOpenFollowers}
                  onKeyDown={(event) =>
                    event.key === "Enter" && onOpenFollowers()
                  }
                  className="cursor-pointer tabular-nums hover:text-white"
                >
                  <span className="font-semibold text-gray-200">
                    {metaLoading ? (
                      <span className="inline-block h-4 w-8 animate-pulse rounded bg-white/10 align-middle" />
                    ) : (
                      followersCount
                    )}
                  </span>{" "}
                  Followers
                </span>
                <span aria-hidden="true">•</span>
                <span
                  role="button"
                  tabIndex={0}
                  onClick={onOpenFollowing}
                  onKeyDown={(event) =>
                    event.key === "Enter" && onOpenFollowing()
                  }
                  className="cursor-pointer tabular-nums hover:text-white"
                >
                  <span className="font-semibold text-gray-200">
                    {metaLoading ? (
                      <span className="inline-block h-4 w-8 animate-pulse rounded bg-white/10 align-middle" />
                    ) : (
                      followingCount
                    )}
                  </span>{" "}
                  Following
                </span>
              </p>

              <p className="mt-1 text-sm text-gray-400">
                {formatProfileMetadataLine(profile)}
              </p>

              <p className="mt-2 whitespace-pre-wrap break-words px-4 text-sm leading-relaxed text-gray-300 md:px-0">
                {profile.bio || "No bio yet"}
              </p>

              <ProfileTradeRoomSection
                isOwnProfile={isOwnProfile}
                hasRoom={hasRoom}
                canShowVisitorRoomCta={canShowVisitorRoomCta}
                onCreateRoom={onCreateRoom}
                onViewRoom={onViewRoom}
              />
            </div>
          </div>

          {isOwnProfile ? (
            <div className="absolute right-4 top-4 z-10 flex items-center gap-2 sm:relative sm:right-auto sm:top-auto sm:mt-0 sm:flex sm:shrink-0 sm:justify-end sm:pt-2">
              <ProfileCreateMenu
                onCreateStory={onCreateStory}
                onCreatePost={onCreatePost}
                onCreateReel={onCreateReel}
                onCreateQuickTrade={onCreateQuickTrade}
              />
              <button
                type="button"
                onClick={onEditProfile}
                className="inline-flex items-center justify-center rounded-lg border border-white/10 bg-white/5 p-2 text-gray-100 transition hover:bg-white/10 sm:hidden"
                aria-label="Edit Profile"
                title="Edit Profile"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1.75"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  className="h-5 w-5"
                  aria-hidden
                >
                  <path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l-.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z" />
                  <circle cx="12" cy="12" r="3" />
                </svg>
              </button>
            </div>
          ) : null}
        </div>
      </div>
    </div>
  )
}
