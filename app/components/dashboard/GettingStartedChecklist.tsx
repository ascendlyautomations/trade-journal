"use client"

import Link from "next/link"
import { useCallback, useEffect, useState } from "react"
import HelpHint from "@/app/components/ui/HelpHint"
import type { GettingStartedProgress } from "@/lib/gettingStartedChecklist"
import {
  GETTING_STARTED_COLLAPSED_STORAGE_KEY,
  GETTING_STARTED_ITEM_HELP,
  readGettingStartedCollapsedPreference,
  readGettingStartedSessionDismissed,
  writeGettingStartedCollapsedPreference,
  writeGettingStartedSessionDismissed,
} from "@/lib/gettingStartedChecklist"
import { profilePath } from "@/lib/profileRoutes"
import PopularTradeRoomsModal from "./PopularTradeRoomsModal"

export type GettingStartedChecklistProps = {
  progress: GettingStartedProgress
  userId: string
  profileId?: string
  firstPrivateTradeId?: string | null
  onChecklistRefresh?: () => void
  /** When true, always show tasks (no collapse toggle). Used in mobile drawer. */
  alwaysExpanded?: boolean
  /** When false, start collapsed unless user previously expanded. */
  defaultExpanded?: boolean
  /** When true, omit outer card chrome (parent supplies container). */
  embedded?: boolean
  /** Dashboard empty-state: show Welcome headline above Getting Started. */
  showWelcomeHeading?: boolean
  className?: string
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
        ? `${profilePath({ id: profileId })}?tab=posts&createPost=1`
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
  const help = <HelpHint body={GETTING_STARTED_ITEM_HELP[item.id].body} />

  const labelRow = (
    <span
      className={`flex min-w-0 flex-1 items-start gap-3 text-sm md:text-base ${
        item.complete ? "text-gray-400" : "text-gray-200"
      }`}
    >
      <span className="mt-0.5 shrink-0 text-base leading-none" aria-hidden>
        {item.complete ? "☑" : "☐"}
      </span>
      <span
        className={
          item.complete
            ? "min-w-0 flex-1 line-through"
            : "min-w-0 flex-1 font-medium text-gray-100"
        }
      >
        {item.label}
      </span>
    </span>
  )

  if (item.complete) {
    return (
      <li className="flex items-center gap-2">
        {labelRow}
        {help}
      </li>
    )
  }

  if (item.id === "room") {
    return (
      <li className="flex items-center gap-2">
        <button
          type="button"
          onClick={onOpenPopularRooms}
          className="-mx-2 min-w-0 flex-1 rounded-lg px-2 py-1 text-left transition hover:bg-white/5"
        >
          {labelRow}
        </button>
        {help}
      </li>
    )
  }

  const href = itemHref(item.id, { profileId, firstPrivateTradeId })
  return (
    <li className="flex items-center gap-2">
      {href ? (
        <Link
          href={href}
          className="-mx-2 min-w-0 flex-1 rounded-lg px-2 py-1 transition hover:bg-white/5"
        >
          {labelRow}
        </Link>
      ) : (
        <div className="min-w-0 flex-1">{labelRow}</div>
      )}
      {help}
    </li>
  )
}

export default function GettingStartedChecklist({
  progress,
  userId,
  profileId,
  firstPrivateTradeId,
  onChecklistRefresh,
  alwaysExpanded = false,
  defaultExpanded = true,
  embedded = false,
  showWelcomeHeading = false,
  className = "",
}: GettingStartedChecklistProps) {
  const { items, completedCount, totalCount } = progress
  const progressPct =
    totalCount > 0 ? Math.round((completedCount / totalCount) * 100) : 0

  const [expanded, setExpanded] = useState(true)
  const [popularRoomsOpen, setPopularRoomsOpen] = useState(false)

  useEffect(() => {
    if (alwaysExpanded) {
      setExpanded(true)
      return
    }
    if (readGettingStartedSessionDismissed(userId)) {
      setExpanded(false)
      return
    }
    if (readGettingStartedCollapsedPreference(userId)) {
      setExpanded(false)
      return
    }
    setExpanded(defaultExpanded)
  }, [userId, alwaysExpanded, defaultExpanded])

  const toggleExpanded = useCallback(() => {
    if (alwaysExpanded) return
    setExpanded((prev) => {
      const next = !prev
      if (!next) {
        writeGettingStartedSessionDismissed(userId)
        writeGettingStartedCollapsedPreference(userId, true)
      } else {
        writeGettingStartedCollapsedPreference(userId, false)
      }
      return next
    })
  }, [userId, alwaysExpanded])

  const isExpanded = alwaysExpanded || expanded

  const shellClass = embedded
    ? className
    : `rounded-xl border border-white/10 bg-white/5 p-6 backdrop-blur-md md:p-8 ${className}`

  const header = alwaysExpanded ? (
    <div className="flex w-full items-center justify-between gap-3">
      <h3 className="text-lg font-semibold text-white">Getting Started</h3>
      <p className="text-sm font-medium tabular-nums text-gray-300">
        {completedCount} / {totalCount} Complete
      </p>
    </div>
  ) : (
    <button
      type="button"
      onClick={toggleExpanded}
      className="flex w-full items-center justify-between gap-3 text-left"
      aria-expanded={isExpanded}
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
          title={isExpanded ? "Collapse" : "Expand"}
        >
          {isExpanded ? "▼" : "▶"}
        </span>
      </div>
    </button>
  )

  return (
    <>
      <div className={shellClass}>
        {showWelcomeHeading ? (
          <h2 className="mb-4 text-xl font-semibold text-blue-300 md:mb-5 md:text-3xl">
            Welcome to TradeTraxs
          </h2>
        ) : null}
        {header}

        {isExpanded ? (
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
