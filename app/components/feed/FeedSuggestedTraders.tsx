"use client"

import Link from "next/link"
import { useEffect, useMemo, useState } from "react"
import FollowButton from "@/app/components/FollowButton"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import Skeleton from "@/app/components/ui/Skeleton"
import {
  fetchSuggestedTraderPool,
  selectSuggestedTraders,
  SUGGESTED_TRADERS_LIMIT,
  type SuggestedTrader,
} from "@/lib/feedSuggestedTraders"
import { normalizeTraderType } from "@/lib/traderType"
import { profilePath } from "@/lib/profileRoutes"
import { isNativeIos } from "@/lib/nativePlatform"
import { scheduleDeferredWork } from "@/lib/scheduleDeferredWork"
import { supabase } from "@/lib/supabaseClient"

type FeedSuggestedTradersProps = {
  viewerId: string
  followingIds: readonly string[]
  onFollowingChange: (targetUserId: string, following: boolean) => void
}

function traderContext(profile: SuggestedTrader): string | null {
  const traderType = normalizeTraderType(profile.trader_type)
  const style = profile.trading_style?.trim() || null
  const parts = [traderType || null, style].filter(Boolean)
  return parts.length > 0 ? parts.join(" · ") : null
}

export default function FeedSuggestedTraders({
  viewerId,
  followingIds,
  onFollowingChange,
}: FeedSuggestedTradersProps) {
  const [pool, setPool] = useState<SuggestedTrader[] | null>(null)
  const [blockedIds, setBlockedIds] = useState<string[]>([])

  useEffect(() => {
    let cancelled = false
    let started = false
    const desktop = window.matchMedia("(min-width: 1280px)")

    const load = () => {
      if (cancelled || started || isNativeIos() || !desktop.matches) return
      started = true
      scheduleDeferredWork(() => {
        if (cancelled) return
        void fetchSuggestedTraderPool(supabase, viewerId).then((result) => {
          if (cancelled) return
          setPool(result.profiles)
          setBlockedIds(result.blockedIds)
        })
      })
    }

    load()
    desktop.addEventListener("change", load)
    return () => {
      cancelled = true
      desktop.removeEventListener("change", load)
    }
  }, [viewerId])

  const followingSet = useMemo(() => new Set(followingIds), [followingIds])

  const traders = useMemo(() => {
    if (!pool) return []
    return selectSuggestedTraders(pool, {
      viewerId,
      followingIds,
      blockedIds,
      limit: SUGGESTED_TRADERS_LIMIT,
    })
  }, [pool, viewerId, followingIds, blockedIds])

  if (pool && traders.length === 0) return null

  return (
    <section
      aria-label="Suggested Traders"
      className="rounded-xl border border-white/10 bg-white/5 p-3"
    >
      <div className="mb-3 flex items-center justify-between gap-3">
        <h2 className="text-sm font-semibold text-white">Suggested Traders</h2>
        <Link
          href="/explore"
          prefetch={false}
          className="shrink-0 text-xs font-medium text-blue-300 hover:text-blue-200"
        >
          See All
        </Link>
      </div>

      {pool == null ? (
        <div className="space-y-3" aria-hidden="true">
          {Array.from({ length: 5 }, (_, index) => (
            <div key={index} className="flex items-center gap-2.5">
              <Skeleton className="h-9 w-9 shrink-0 rounded-full" />
              <div className="min-w-0 flex-1 space-y-1.5">
                <Skeleton className="h-3 w-24" />
                <Skeleton className="h-2.5 w-16" />
              </div>
              <Skeleton className="h-7 w-16 shrink-0 rounded-md" />
            </div>
          ))}
        </div>
      ) : (
        <ul className="space-y-3">
          {traders.map((profile) => {
            const displayName =
              profile.name?.trim() || profile.username?.trim() || "Trader"
            const username = profile.username?.trim()
            const context = traderContext(profile)
            const href = profilePath({
              id: profile.id,
              username: profile.username,
            })

            return (
              <li key={profile.id} className="flex items-center gap-2.5">
                <Link href={href} prefetch={false} className="shrink-0">
                  <ProfileAvatarImg
                    src={profile.avatar_url}
                    className="h-9 w-9 border border-white/10"
                  />
                </Link>
                <div className="min-w-0 flex-1">
                  <Link href={href} prefetch={false} className="block min-w-0">
                    <p className="truncate text-sm font-semibold text-white">
                      {displayName}
                    </p>
                    {username ? (
                      <p className="truncate text-xs text-gray-300">
                        @{username}
                      </p>
                    ) : null}
                  </Link>
                  {context ? (
                    <p className="truncate text-xs text-gray-400">{context}</p>
                  ) : null}
                </div>
                <FollowButton
                  targetUserId={profile.id}
                  currentUserId={viewerId}
                  targetIsPrivate={false}
                  followingIds={followingSet}
                  onFollowingChange={onFollowingChange}
                />
              </li>
            )
          })}
        </ul>
      )}
    </section>
  )
}
