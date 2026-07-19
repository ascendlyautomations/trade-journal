"use client"

import Link from "next/link"
import type { ReactNode } from "react"
import EmptyState from "@/app/components/ui/EmptyState"
import { SkeletonTradeCard } from "@/app/components/ui/skeletons"
import ProfilePrivateTabMessage from "./ProfilePrivateTabMessage"
import type { ProfileTradeRow } from "./profileTypes"

type ProfileTradesTabProps = {
  trades: ProfileTradeRow[]
  loading: boolean
  isOwnProfile: boolean
  canView: boolean
  hasMore: boolean
  onLoadMore: () => void
  renderTrade: (trade: ProfileTradeRow) => ReactNode
}

export default function ProfileTradesTab({
  trades,
  loading,
  isOwnProfile,
  canView,
  hasMore,
  onLoadMore,
  renderTrade,
}: ProfileTradesTabProps) {
  return (
    <div className="mt-4 w-full pb-8">
      {loading && trades.length === 0 ? (
        <div className="grid grid-cols-1 gap-x-6 gap-y-8 md:grid-cols-2">
          {Array.from({ length: 4 }).map((_, i) => (
            <SkeletonTradeCard key={i} />
          ))}
        </div>
      ) : trades.length === 0 ? (
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
          <p className="text-center text-sm text-gray-400">
            No public trades yet.
          </p>
        )
      ) : (
        <div className="grid grid-cols-1 gap-x-6 gap-y-8 md:grid-cols-2">
          {trades.map((trade) => (
            <div key={trade.id} id={`trade-${trade.id}`}>
              {renderTrade(trade)}
            </div>
          ))}
        </div>
      )}
      {hasMore && canView ? (
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
