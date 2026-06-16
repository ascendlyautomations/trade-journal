"use client"

import Link from "next/link"
import { useCallback, useEffect, useState } from "react"
import HelpHint from "@/app/components/ui/HelpHint"
import type { GettingStartedProgress } from "@/lib/gettingStartedChecklist"
import {
  GETTING_STARTED_COLLAPSED_STORAGE_KEY,
  GETTING_STARTED_ITEM_HELP,
  readGettingStartedCollapsedPreference,
  writeGettingStartedCollapsedPreference,
} from "@/lib/gettingStartedChecklist"
import { profilePath } from "@/lib/profileRoutes"
import PopularTradeRoomsModal from "./PopularTradeRoomsModal"

export type GettingStartedChecklistProps = {
  progress: GettingStartedProgress
  userId: string
  profileId?: string
  firstPrivateTradeId?: string | null
  onChecklistRefresh?: () => void
  onDismissComplete?: () => void
}

function itemHref(
  id: GettingStartedProgress["items"][number]["id"],
  options: { profileId?: string; firstPrivateTradeId?: string | null }
): string | undefined {
  const { profileId, firstPrivateTradeId } = options
  switch (id) {
    case "profile":
      return "/settings"
    case "trade":
      return "/app"
    case "post":
      return profileId
        ? `${profilePath({ id: profileId })}?createPost=1`
        : undefined
    case "follow":
      return "/explore"
    case "public":
      if (firstPrivateTradeId) {
        return `/trades?edit=${encodeURIComponent(firstPrivateTradeId)}`
      }
      return "/trades"
    default:
      return undefined
  }
}

function ChecklistItemRow({
  item,
  profileId,
  firstPrivateTradeId,
  onOpenPopularRooms,
}: {
  item: GettingStartedProgress["items"][number]
  profileId?: string
  firstPrivateTradeId?: string | null
  onOpenPopularRooms: () => void
}) {
  const row = (
    <span
      className={`flex items-start gap-3 text-sm md:text-base ${
        item.complete ? "text-gray-500" : "text-gray-200"
      }`}
    >
      <span className="mt-0.5 shrink-0 text-base leading-none" aria-hidden>
        {item.complete ? "☑" : "☐"}
      </span>
      <span className="flex min-w-0 flex-1 items-center gap-2">
        <span
          className={
            item.complete ? "line-through" : "font-medium text-gray-100"
          }
        >
          {item.label}
        </span>
        <HelpHint body={GETTING_STARTED_ITEM_HELP[item.id].body} />
      </span>
    </span>
  )

  if (item.complete) {
    return <li key={item.id}>{row}</li>
  }

  if (item.id === "room") {
    return (
      <li key={item.id}>
        <button
          type="button"
          onClick={onOpenPopularRooms}
          className="block w-full rounded-lg text-left transition hover:bg-white/5 -mx-2 px-2 py-1"
        >
          {row}
        </button>
      </li>
    )
  }

  const href = itemHref(item.id, { profileId, firstPrivateTradeId })
  return (
    <li key={item.id}>
      {href ? (
        <Link
          href={href}
          className="block rounded-lg transition hover:bg-white/5 -mx-2 px-2 py-1"
        >
          {row}
        </Link>
      ) : (
        row
      )}
    </li>
  )
}

export default function GettingStartedChecklist({
  progress,
  userId,
  profileId,
  firstPrivateTradeId,
  onChecklistRefresh,
  onDismissComplete,
}: GettingStartedChecklistProps) {
  const { items, completedCount, totalCount, allComplete } = progress
  const progressPct =
    totalCount > 0 ? Math.round((completedCount / totalCount) * 100) : 0

  const [expanded, setExpanded] = useState(true)
  const [popularRoomsOpen, setPopularRoomsOpen] = useState(false)

  useEffect(() => {
    setExpanded(!readGettingStartedCollapsedPreference(userId))
  }, [userId])

  const toggleExpanded = useCallback(() => {
    setExpanded((prev) => {
      const next = !prev
      writeGettingStartedCollapsedPreference(userId, !next)
      return next
    })
  }, [userId])

  return (
    <>
      <div className="rounded-xl border border-white/10 bg-white/5 p-6 backdrop-blur-md md:p-8">
        {allComplete ? (
          <>
            <h3 className="text-lg font-semibold text-white md:text-xl">
              🎉 You Have Completed All Onboarding Tasks
            </h3>
            <p className="mt-2 text-base font-medium text-gray-100 md:text-lg">
              Enjoy TradeTraxs!
            </p>
            <p className="mt-2 max-w-2xl text-sm text-gray-400 md:text-base">
              You&apos;re ready to track trades, share ideas, and grow with the
              community.
            </p>
            <button
              type="button"
              onClick={onDismissComplete}
              className="mt-6 rounded-lg border border-white/20 bg-white/10 px-4 py-2 text-sm font-semibold text-white transition hover:bg-white/15"
            >
              Dismiss
            </button>
          </>
        ) : (
          <>
            <button
              type="button"
              onClick={toggleExpanded}
              className="flex w-full items-center justify-between gap-3 text-left"
              aria-expanded={expanded}
            >
              <h3 className="text-lg font-semibold text-white md:text-xl">
                Getting Started
              </h3>
              <div className="flex items-center gap-2">
                <p className="text-sm font-medium tabular-nums text-gray-300">
                  {completedCount} / {totalCount} Complete
                </p>
                <span
                  className="text-sm text-gray-400"
                  aria-hidden
                  title={expanded ? "Collapse" : "Expand"}
                >
                  {expanded ? "▼" : "▶"}
                </span>
              </div>
            </button>

            {expanded ? (
              <>
                <div
                  className="mt-4 h-2 overflow-hidden rounded-full bg-white/10"
                  role="progressbar"
                  aria-valuenow={completedCount}
                  aria-valuemin={0}
                  aria-valuemax={totalCount}
                  aria-label={`Getting started progress: ${completedCount} of ${totalCount} complete`}
                >
                  <div
                    className="h-full rounded-full bg-gradient-to-r from-blue-500 to-emerald-500 transition-[width] duration-300"
                    style={{ width: `${progressPct}%` }}
                  />
                </div>

                <ul className="mt-5 space-y-3">
                  {items.map((item) => (
                    <ChecklistItemRow
                      key={item.id}
                      item={item}
                      profileId={profileId}
                      firstPrivateTradeId={firstPrivateTradeId}
                      onOpenPopularRooms={() => setPopularRoomsOpen(true)}
                    />
                  ))}
                </ul>
              </>
            ) : null}
          </>
        )}
      </div>

      <PopularTradeRoomsModal
        open={popularRoomsOpen}
        onClose={() => setPopularRoomsOpen(false)}
        onJoined={onChecklistRefresh}
      />
    </>
  )
}

export { GETTING_STARTED_COLLAPSED_STORAGE_KEY }
