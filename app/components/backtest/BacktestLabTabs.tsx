"use client"

export type BacktestLabTab = "overview" | "strategies" | "calendar" | "trades"

const TAB_ORDER: BacktestLabTab[] = [
  "overview",
  "strategies",
  "calendar",
  "trades",
]

const TAB_LABELS: Record<BacktestLabTab, string> = {
  overview: "Overview",
  strategies: "Strategies",
  calendar: "Calendar",
  trades: "Trades & Review",
}

type BacktestLabTabsProps = {
  value: BacktestLabTab
  onChange: (tab: BacktestLabTab) => void
  needsReviewCount?: number
}

export default function BacktestLabTabs({
  value,
  onChange,
  needsReviewCount = 0,
}: BacktestLabTabsProps) {
  return (
    <div
      role="tablist"
      aria-label="Backtest Lab sections"
      className="backtest-lab-tabs relative mb-5 grid w-full grid-cols-2 sm:grid-cols-4"
    >
      {TAB_ORDER.map((tab) => {
        const selected = value === tab
        return (
          <button
            key={tab}
            type="button"
            role="tab"
            aria-selected={selected}
            onClick={() => onChange(tab)}
            className="backtest-lab-tab inline-flex items-center justify-center gap-1.5"
          >
            <span className="truncate">{TAB_LABELS[tab]}</span>
            {tab === "trades" && needsReviewCount > 0 ? (
              <span className="inline-flex min-w-[1.25rem] shrink-0 items-center justify-center rounded-full bg-amber-500/35 px-1.5 py-0.5 text-[10px] font-bold text-amber-100">
                {needsReviewCount > 99 ? "99+" : needsReviewCount}
              </span>
            ) : null}
          </button>
        )
      })}
    </div>
  )
}

export function backtestLabTabPanelId(tab: BacktestLabTab): string {
  return `backtest-lab-panel-${tab}`
}
