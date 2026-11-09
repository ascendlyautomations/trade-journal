"use client"

import Link from "next/link"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import type { ExploreLiveTraderNow } from "@/lib/exploreLiveTradersNowClient"
import { buildTradeRoomHref } from "@/lib/notificationsDisplay"
import { profilePath } from "@/lib/profileRoutes"

const PANEL_CLASS =
  "rounded-xl border border-white/10 bg-white/5 p-2.5 backdrop-blur-md md:p-4"

type Props = {
  items: ExploreLiveTraderNow[]
  loading: boolean
  error: string | null
  onRetry: () => void
}

export default function ExploreLiveTradersNowSection({
  items,
  loading,
  error,
  onRetry,
}: Props) {
  if (!loading && !error && items.length === 0) {
    return null
  }

  return (
    <section className={PANEL_CLASS}>
      <div className="mb-3">
        <h2 className="text-[15px] font-semibold text-[color:var(--tt-text,#f0f3f6)] md:text-base">
          Live Traders Now
        </h2>
        <p className="mt-0.5 text-[12px] text-[color:var(--tt-text-tertiary,#a8b3c2)] md:text-sm">
          Public livestreams happening in Trade Rooms
        </p>
      </div>

      {loading ? (
        <div className="flex gap-2.5 overflow-hidden">
          {Array.from({ length: 3 }).map((_, i) => (
            <div
              key={i}
              className="h-[148px] w-[168px] shrink-0 animate-pulse rounded-[10px] bg-white/10"
            />
          ))}
        </div>
      ) : error ? (
        <div className="flex flex-col items-start gap-2 py-2">
          <p className="text-sm text-[color:var(--tt-text-muted,#c0cad6)]">{error}</p>
          <button
            type="button"
            onClick={onRetry}
            className="rounded-lg bg-blue-500 px-3 py-1.5 text-sm font-semibold text-white hover:bg-blue-600"
          >
            Retry
          </button>
        </div>
      ) : (
        <div className="tt-mobile-web-hscroll -mx-1 flex gap-2.5 overflow-x-auto px-1 pb-1 [scrollbar-width:none] md:mx-0 md:px-0 [&::-webkit-scrollbar]:hidden">
          {items.map((item) => {
            const displayName =
              item.broadcasterDisplayName?.trim() ||
              item.broadcasterUsername?.trim() ||
              "Trader"
            const username = item.broadcasterUsername?.trim()
            const roomHref = item.roomSlug
              ? buildTradeRoomHref(item.roomSlug, { live: true })
              : `/community?room=${encodeURIComponent(item.roomId)}&live=1`
            const profileHref = profilePath({
              id: item.broadcasterUserId,
              username: item.broadcasterUsername ?? undefined,
            })
            return (
              <article
                key={item.broadcastSessionId}
                className="relative flex w-[168px] shrink-0 flex-col rounded-[10px] bg-[color:var(--tt-surface-nested,#1a222c)] p-2.5"
              >
                <span className="absolute right-2 top-2 rounded-full bg-red-500/90 px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wide text-white">
                  Live
                </span>
                <Link href={profileHref} prefetch={false} className="min-w-0">
                  <ProfileAvatarImg
                    src={item.broadcasterAvatarUrl}
                    className="h-[52px] w-[52px]"
                  />
                  <p className="mt-2 truncate pr-10 text-[13px] font-semibold text-[color:var(--tt-text,#f0f3f6)]">
                    {displayName}
                  </p>
                  {username ? (
                    <p className="truncate text-[11px] text-[color:var(--tt-text-muted,#c0cad6)]">
                      @{username}
                    </p>
                  ) : null}
                </Link>
                <p className="mt-1 line-clamp-2 text-[11px] text-[color:var(--tt-text-tertiary,#a8b3c2)]">
                  {item.roomName}
                </p>
                {typeof item.viewerCount === "number" ? (
                  <p className="mt-1 text-[11px] text-[color:var(--tt-text-tertiary,#a8b3c2)]">
                    {item.viewerCount} watching
                  </p>
                ) : null}
                <Link
                  href={roomHref}
                  className="mt-2 block rounded-lg bg-[color:color-mix(in_srgb,var(--tt-accent,#4ec4e0)_35%,transparent)] px-2 py-1.5 text-center text-[12px] font-semibold text-[color:var(--tt-text,#f0f3f6)] hover:opacity-90"
                >
                  Watch
                </Link>
              </article>
            )
          })}
        </div>
      )}
    </section>
  )
}
