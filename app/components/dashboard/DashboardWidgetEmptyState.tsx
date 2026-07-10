"use client"

import Link from "next/link"
import EmptyState from "@/app/components/ui/EmptyState"

export type DashboardWidgetEmptyVariant =
  | "no-trades"
  | "needs-more-trades"
  | "needs-direction"
  | "needs-duration"

const COPY: Record<
  DashboardWidgetEmptyVariant,
  { icon: string; title: string; description: string }
> = {
  "no-trades": {
    icon: "📈",
    title: "Upload your first trade to unlock this insight",
    description:
      "Add a trade manually or import your history to start tracking performance.",
  },
  "needs-more-trades": {
    icon: "📊",
    title: "Complete more trades to unlock this statistic",
    description:
      "Keep journaling to reveal trends, patterns, and performance breakdowns.",
  },
  "needs-direction": {
    icon: "↕️",
    title: "Add trade direction to unlock this comparison",
    description:
      "Include long or short on your trades to compare side performance.",
  },
  "needs-duration": {
    icon: "⏱️",
    title: "Add hold time to unlock this insight",
    description:
      "Include entry and exit times to analyze how long your winners and losers run.",
  },
}

const addTradeButtonClass =
  "rounded-lg bg-blue-500 px-3 py-1.5 text-sm font-semibold text-white transition hover:bg-blue-600 disabled:hover:bg-blue-500"

const secondaryButtonClass =
  "rounded-lg border border-white/20 bg-white/10 px-3 py-1.5 text-sm font-semibold text-white transition hover:bg-white/15"

type DashboardWidgetEmptyStateProps = {
  variant: DashboardWidgetEmptyVariant
  showImportCsv?: boolean
  className?: string
}

export default function DashboardWidgetEmptyState({
  variant,
  showImportCsv = false,
  className,
}: DashboardWidgetEmptyStateProps) {
  const { icon, title, description } = COPY[variant]

  return (
    <EmptyState
      icon={icon}
      title={title}
      description={description}
      action={
        <div className="flex flex-wrap items-center justify-center gap-2">
          <Link href="/app" className={addTradeButtonClass}>
            + Add Trade
          </Link>
          {showImportCsv ? (
            <Link href="/import" className={secondaryButtonClass}>
              Import CSV
            </Link>
          ) : null}
        </div>
      }
      className={className}
    />
  )
}
