"use client"

import Link from "next/link"
import { useEffect, useRef, useState, type ReactNode } from "react"
import EmptyState from "@/app/components/ui/EmptyState"
import { SkeletonTradeCard } from "@/app/components/ui/skeletons"
import ProfilePrivateTabMessage from "./ProfilePrivateTabMessage"
import ProfileTradeGridTile from "./ProfileTradeGridTile"
import { PROFILE_TRADES_PAGE_SIZE_MOBILE } from "./profileTradesPagination"
import {
  useProfileTradesViewMode,
  type ProfileTradesViewMode,
} from "./useProfileTradesViewMode"
import type { ProfileTradeRow } from "./profileTypes"

const MAX_MD_QUERY = "(max-width: 767px)"

type ProfileTradesTabProps = {
  trades: ProfileTradeRow[]
  loading: boolean
  isOwnProfile: boolean
  canView: boolean
  hasMore: boolean
  onLoadMore: () => void
  /** Full trade card feed (list mode + desktop). */
  renderTrade: (trade: ProfileTradeRow) => ReactNode
  /** Opens the existing profile trade detail modal. */
  onOpenTrade: (trade: ProfileTradeRow) => void
}

function TradesViewToggle({
  value,
  onChange,
}: {
  value: ProfileTradesViewMode
  onChange: (mode: ProfileTradesViewMode) => void
}) {
  return (
    <div
      role="tablist"
      aria-label="Trades view"
      className="mb-2 flex justify-end"
    >
      <div className="inline-flex rounded-lg border border-white/10 bg-white/5 p-0.5">
        {(["grid", "list"] as const).map((mode) => {
          const selected = value === mode
          return (
            <button
              key={mode}
              type="button"
              role="tab"
              aria-selected={selected}
              onClick={() => onChange(mode)}
              className={`rounded-md px-2.5 py-1 text-[11px] font-semibold tracking-wide transition-colors ${
                selected
                  ? "bg-white/15 text-white"
                  : "text-gray-400 hover:text-gray-200"
              }`}
            >
              {mode === "grid" ? "Grid" : "List"}
            </button>
          )
        })}
      </div>
    </div>
  )
}

function ProfileTradeGridSkeletonTile() {
  return (
    <div className="overflow-hidden rounded-md border border-white/10 bg-white/5">
      <div className="aspect-square animate-pulse bg-white/5" />
      <div className="h-[40px] border-t border-white/10" />
    </div>
  )
}

function useIsMobileTradesLayout() {
  const [isMobile, setIsMobile] = useState(() =>
    typeof window !== "undefined"
      ? window.matchMedia(MAX_MD_QUERY).matches
      : false
  )

  useEffect(() => {
    const mq = window.matchMedia(MAX_MD_QUERY)
    const sync = () => setIsMobile(mq.matches)
    sync()
    mq.addEventListener("change", sync)
    return () => mq.removeEventListener("change", sync)
  }, [])

  return isMobile
}

function getAppScrollRoot(): Element | null {
  if (typeof document === "undefined") return null
  const el = document.querySelector("[data-tt-app-scroll]")
  return el instanceof HTMLElement ? el : null
}

export default function ProfileTradesTab({
  trades,
  loading,
  isOwnProfile,
  canView,
  hasMore,
  onLoadMore,
  renderTrade,
  onOpenTrade,
}: ProfileTradesTabProps) {
  const { viewMode, setViewMode } = useProfileTradesViewMode()
  const isMobile = useIsMobileTradesLayout()
  const sentinelRef = useRef<HTMLDivElement>(null)
  const loadingRef = useRef(loading)
  const hasMoreRef = useRef(hasMore)
  loadingRef.current = loading
  hasMoreRef.current = hasMore

  // Mobile: infinite scroll via IntersectionObserver (no Load More button).
  useEffect(() => {
    if (!isMobile || !canView || !hasMore) return
    const sentinel = sentinelRef.current
    if (!sentinel) return

    const root = getAppScrollRoot()
    const observer = new IntersectionObserver(
      (entries) => {
        if (!entries.some((entry) => entry.isIntersecting)) return
        if (loadingRef.current || !hasMoreRef.current) return
        onLoadMore()
      },
      {
        root,
        // Prefetch ~1–2 grid rows before the absolute bottom.
        rootMargin: "480px 0px",
        threshold: 0,
      }
    )

    observer.observe(sentinel)
    return () => observer.disconnect()
  }, [canView, hasMore, isMobile, onLoadMore, trades.length, viewMode])

  const emptyState =
    isOwnProfile ? (
      <EmptyState
        title="Share Your First Trade"
        description="Your public trading history will appear here."
        action={
          <Link
            href="/app"
            className="text-sm font-medium text-blue-300 hover:text-blue-200"
          >
            Add Trade →
          </Link>
        }
        className="py-10"
      />
    ) : !canView ? (
      <ProfilePrivateTabMessage variant="trades" />
    ) : (
      <p className="text-center text-sm text-gray-400">No public trades yet.</p>
    )

  const showMobileGrid = isMobile && viewMode === "grid"
  const skeletonCount =
    trades.length === 0 ? PROFILE_TRADES_PAGE_SIZE_MOBILE : 3

  return (
    <div className="mt-1 w-full pb-8 sm:mt-4">
      {isMobile && (trades.length > 0 || loading) ? (
        <TradesViewToggle value={viewMode} onChange={setViewMode} />
      ) : null}

      {loading && trades.length === 0 ? (
        isMobile ? (
          <div className="grid grid-cols-3 gap-1">
            {Array.from({ length: PROFILE_TRADES_PAGE_SIZE_MOBILE }).map(
              (_, i) => (
                <ProfileTradeGridSkeletonTile key={i} />
              )
            )}
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-x-6 gap-y-4 md:grid-cols-2 md:gap-y-8">
            {Array.from({ length: 4 }).map((_, i) => (
              <SkeletonTradeCard key={i} />
            ))}
          </div>
        )
      ) : trades.length === 0 ? (
        emptyState
      ) : showMobileGrid ? (
        <div className="grid grid-cols-3 gap-1">
          {trades.map((trade) => (
            <div key={trade.id} id={`trade-${trade.id}`}>
              <ProfileTradeGridTile
                trade={trade}
                onOpenTrade={onOpenTrade}
              />
            </div>
          ))}
          {loading
            ? Array.from({ length: skeletonCount }).map((_, i) => (
                <ProfileTradeGridSkeletonTile key={`sk-${i}`} />
              ))
            : null}
        </div>
      ) : (
        <div
          className={
            isMobile
              ? "grid grid-cols-1 gap-y-4"
              : "grid grid-cols-1 gap-x-6 gap-y-4 md:grid-cols-2 md:gap-y-8"
          }
        >
          {trades.map((trade) => (
            <div key={trade.id} id={`trade-${trade.id}`}>
              {renderTrade(trade)}
            </div>
          ))}
          {isMobile && loading
            ? Array.from({ length: 2 }).map((_, i) => (
                <SkeletonTradeCard key={`sk-list-${i}`} />
              ))
            : null}
        </div>
      )}

      {isMobile && hasMore && canView ? (
        <div
          ref={sentinelRef}
          className="h-1 w-full shrink-0"
          aria-hidden
        />
      ) : null}

      {!isMobile && hasMore && canView ? (
        <button
          type="button"
          onClick={onLoadMore}
          disabled={loading}
          className="mt-4 w-full rounded bg-white/10 py-2 hover:bg-white/20"
        >
          Load More
        </button>
      ) : null}
    </div>
  )
}
