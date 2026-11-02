"use client"

import Link from "next/link"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import { MOBILE_WEB_CARD_CLASS } from "@/lib/mobileWebPageSurface"
import type { LeaderboardTableRow } from "@/lib/leaderboardPresentation"
import { profilePath } from "@/lib/profileRoutes"
import { pnlTextClassName } from "@/lib/formatDisplay"

type LeaderboardProfile = {
  id?: string
  username?: string | null
  name?: string | null
  avatar_url?: string | null
}

type MobileWebLeaderboardSurfaceProps = {
  rows: LeaderboardTableRow[]
  profilesById: Record<string, LeaderboardProfile | undefined>
  currentUserId?: string | null
  categoryLabel: string
  onLoadMore?: () => void
  loadingMore?: boolean
  showLoadMore?: boolean
}

function displayName(profile: LeaderboardProfile | undefined, userId: string) {
  return (
    profile?.name?.trim() ||
    profile?.username?.trim() ||
    userId.slice(0, 8)
  )
}

export default function MobileWebLeaderboardSurface({
  rows,
  profilesById,
  currentUserId,
  categoryLabel,
  onLoadMore,
  loadingMore = false,
  showLoadMore = false,
}: MobileWebLeaderboardSurfaceProps) {
  const podium = rows.slice(0, 3)
  const listRows = podium.length > 0 ? rows.slice(3) : rows
  const slot = (rank: number) => podium.find((row) => row.rank === rank)

  return (
    <div className="flex flex-col gap-3">
      {podium.length > 0 ? (
        <div
          className="flex items-end justify-center gap-2 px-1 pb-1 pt-2"
          aria-label="Top three"
        >
          <PodiumSlot
            row={slot(2)}
            profile={slot(2) ? profilesById[slot(2)!.userId] : undefined}
            currentUserId={currentUserId}
            widthClass="w-[29%] shrink-0"
            minHeightClass="min-h-[132px]"
          />
          <PodiumSlot
            row={slot(1)}
            profile={slot(1) ? profilesById[slot(1)!.userId] : undefined}
            currentUserId={currentUserId}
            widthClass="w-[42%] shrink-0"
            minHeightClass="min-h-[168px]"
            emphasized
          />
          <PodiumSlot
            row={slot(3)}
            profile={slot(3) ? profilesById[slot(3)!.userId] : undefined}
            currentUserId={currentUserId}
            widthClass="w-[29%] shrink-0"
            minHeightClass="min-h-[132px]"
          />
        </div>
      ) : null}

      <div className={MOBILE_WEB_CARD_CLASS}>
        <p className="px-3 pt-3 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
          {categoryLabel}
        </p>
        <ul className="divide-y divide-white/10">
          {listRows.map((row) => {
            const profile = profilesById[row.userId]
            const isYou = row.userId === currentUserId
            return (
              <li key={`${row.rank}-${row.userId}`}>
                <Link
                  href={profilePath({
                    id: row.userId,
                    username: profile?.username,
                  })}
                  className="flex items-center gap-3 px-3 py-2.5"
                >
                  <span className="w-7 shrink-0 text-[13px] font-semibold tabular-nums text-muted-foreground">
                    {row.rank}
                  </span>
                  <ProfileAvatarImg
                    src={profile?.avatar_url ?? null}
                    className="h-9 w-9 shrink-0"
                  />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[15px] font-medium text-foreground">
                      {displayName(profile, row.userId)}
                      {isYou ? (
                        <span className="ml-1 text-[11px] text-blue-300">(You)</span>
                      ) : null}
                    </p>
                    {profile?.username?.trim() ? (
                      <p className="truncate text-[11px] text-muted-foreground">
                        @{profile.username.trim()}
                      </p>
                    ) : null}
                    <p className="truncate text-[11px] text-muted-foreground">
                      {row.secondaryMetric}
                    </p>
                  </div>
                  <p
                    className={`shrink-0 text-[14px] font-semibold tabular-nums ${
                      row.pnlForColor != null
                        ? pnlTextClassName(row.pnlForColor)
                        : "text-foreground"
                    }`}
                  >
                    {row.primaryMetric}
                  </p>
                </Link>
              </li>
            )
          })}
        </ul>
        {showLoadMore && onLoadMore ? (
          <div className="flex justify-center px-3 py-3">
            <button
              type="button"
              disabled={loadingMore}
              onClick={onLoadMore}
              className="h-11 rounded-[14px] border border-white/15 px-4 text-sm font-semibold text-foreground disabled:opacity-60"
            >
              {loadingMore ? "Loading…" : "Load more"}
            </button>
          </div>
        ) : null}
      </div>
    </div>
  )
}

function rankBadgeClass(rank: number) {
  if (rank === 1) return "bg-[#d6a62e] text-[#1a1404]"
  if (rank === 2) return "bg-[#9ea8b8] text-[#1a1d22]"
  if (rank === 3) return "bg-[#b87a47] text-[#1a120c]"
  return "bg-[color:var(--tt-accent,#4ec4e0)] text-[#0b141c]"
}

function PodiumSlot({
  row,
  profile,
  currentUserId,
  widthClass,
  minHeightClass,
  emphasized = false,
}: {
  row?: LeaderboardTableRow
  profile?: LeaderboardProfile
  currentUserId?: string | null
  widthClass: string
  minHeightClass: string
  emphasized?: boolean
}) {
  if (!row) return <div className={`min-w-0 ${widthClass} ${minHeightClass}`} />
  const username = profile?.username?.trim()
  return (
    <Link
      href={profilePath({ id: row.userId, username: profile?.username })}
      className={`flex min-w-0 flex-col items-center justify-end rounded-[14px] bg-[color:var(--tt-surface-nested,#1a222c)] px-1.5 py-2.5 ${widthClass} ${minHeightClass} ${
        emphasized
          ? "border border-[color:color-mix(in_srgb,var(--tt-accent)_45%,transparent)]"
          : "border border-white/10"
      }`}
    >
      <div className="relative">
        <ProfileAvatarImg
          src={profile?.avatar_url ?? null}
          className={emphasized ? "h-[68px] w-[68px]" : "h-[52px] w-[52px]"}
        />
        <span
          className={`absolute -right-1 -top-1 rounded-full px-1.5 py-0.5 text-[11px] font-bold ${rankBadgeClass(row.rank)}`}
        >
          {row.rank}
        </span>
      </div>
      <p
        className={`mt-2 w-full truncate text-center font-semibold text-foreground ${
          emphasized ? "text-[13px]" : "text-[11px]"
        }`}
      >
        {displayName(profile, row.userId)}
      </p>
      {username ? (
        <p className="w-full truncate text-center text-[10px] text-muted-foreground">
          @{username}
        </p>
      ) : null}
      <p
        className={`mt-0.5 font-bold tabular-nums ${
          emphasized ? "text-[13px]" : "text-[12px]"
        } ${
          row.pnlForColor != null
            ? pnlTextClassName(row.pnlForColor)
            : "text-foreground"
        }`}
      >
        {row.primaryMetric}
      </p>
      {row.userId === currentUserId ? (
        <p className="text-[10px] text-blue-300">You</p>
      ) : null}
    </Link>
  )
}
