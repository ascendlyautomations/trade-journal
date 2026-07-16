import type { ReactNode } from "react"
import { formatPostedTimestamp } from "@/lib/formatRelativeTime"

export type FeedPostMetaRowProps = {
  label: string
  createdAt?: string | null
  labelClassName?: string
  suffix?: ReactNode
}

/** Type label + published date (e.g. Post · 2h ago). */
export default function FeedPostMetaRow({
  label,
  createdAt,
  labelClassName = "font-medium text-sky-400/90",
  suffix,
}: FeedPostMetaRowProps) {
  const timeLabel = createdAt ? formatPostedTimestamp(createdAt) : ""

  return (
    <p className="truncate text-xs">
      <span className={labelClassName}>{label}</span>
      {timeLabel ? (
        <>
          <span aria-hidden="true" className="mx-1 text-gray-400">
            ·
          </span>
          <time dateTime={createdAt ?? undefined} className="text-gray-400">
            {timeLabel}
          </time>
        </>
      ) : null}
      {suffix}
    </p>
  )
}
