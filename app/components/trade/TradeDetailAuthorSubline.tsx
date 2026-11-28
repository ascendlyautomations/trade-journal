"use client"

import { formatPostedTimestamp } from "@/lib/formatRelativeTime"
import { tradeFirstPublishedAt } from "@/lib/tradePublicationTime"

type TradeDetailAuthorSublineProps = {
  username?: string | null
  trade: { first_published_at?: string | null }
}

/** Feed card parity: `@username · 1d` under display name. */
export default function TradeDetailAuthorSubline({
  username,
  trade,
}: TradeDetailAuthorSublineProps) {
  const publishedAt = tradeFirstPublishedAt(trade)
  const handle = (username ?? "").trim() || "user"
  const timeLabel = publishedAt ? formatPostedTimestamp(publishedAt) : ""

  return (
    <p className="truncate text-xs">
      <span className="text-gray-400">@{handle}</span>
      {timeLabel ? (
        <>
          <span aria-hidden className="mx-1 text-gray-400">
            ·
          </span>
          <time dateTime={publishedAt ?? undefined} className="text-gray-400">
            {timeLabel}
          </time>
        </>
      ) : null}
    </p>
  )
}