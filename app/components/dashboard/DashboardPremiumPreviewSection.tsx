import type { ReactNode } from "react"
import Link from "next/link"
import { buttonVariants, cn } from "@/app/components/ui"
import {
  dashboardInsightCardClass,
  dashboardInsightTitleClass,
} from "@/app/components/dashboard/dashboardInsightStyles"

type DashboardPremiumPreviewSectionProps = {
  className?: string
}

type PreviewCardProps = {
  title: string
  variant: "chart" | "insight"
  children: ReactNode
}

function PreviewCard({ title, variant, children }: PreviewCardProps) {
  const titleClass =
    variant === "chart"
      ? "mb-2 text-xs font-semibold text-blue-300 md:mb-3 md:text-base"
      : dashboardInsightTitleClass

  return (
    <div
      className={cn(
        dashboardInsightCardClass,
        "relative flex min-h-[220px] flex-col overflow-hidden md:min-h-[260px]"
      )}
    >
      <h3 className={titleClass}>
        {title}{" "}
        <span className="text-gray-500" aria-hidden>
          🔒
        </span>
      </h3>
      <div
        className="relative mt-1 flex flex-1 flex-col justify-center blur-[3px] select-none pointer-events-none opacity-75"
        aria-hidden
      >
        {children}
      </div>
      <div
        className="pointer-events-none absolute inset-x-0 bottom-0 h-16 bg-gradient-to-t from-[#0a1628]/60 to-transparent"
        aria-hidden
      />
    </div>
  )
}

function SessionPerformancePlaceholder() {
  return (
    <div className="flex flex-1 flex-col gap-3">
      <p className="text-[11px] text-gray-400 md:text-sm">Trades by Session</p>
      <div className="flex flex-1 items-center justify-center gap-4">
        <div
          className="h-[120px] w-[120px] shrink-0 rounded-full md:h-[140px] md:w-[140px]"
          style={{
            background:
              "conic-gradient(#3b82f6 0deg 130deg, #22c55e 130deg 240deg, #eab308 240deg 360deg)",
          }}
        />
        <div className="space-y-2 text-[10px] text-gray-400 md:text-xs">
          <div className="flex items-center gap-2">
            <span className="h-2 w-2 rounded-full bg-blue-500" />
            <span className="h-2.5 w-16 rounded bg-white/10" />
          </div>
          <div className="flex items-center gap-2">
            <span className="h-2 w-2 rounded-full bg-green-500" />
            <span className="h-2.5 w-14 rounded bg-white/10" />
          </div>
          <div className="flex items-center gap-2">
            <span className="h-2 w-2 rounded-full bg-yellow-500" />
            <span className="h-2.5 w-12 rounded bg-white/10" />
          </div>
        </div>
      </div>
    </div>
  )
}

function WeekdayPerformancePlaceholder() {
  return (
    <div className="w-full px-1">
      <svg
        viewBox="0 0 280 140"
        className="h-[140px] w-full md:h-[160px]"
        preserveAspectRatio="none"
      >
        <line x1="0" y1="120" x2="280" y2="120" stroke="#334155" strokeWidth="1" />
        {[0, 56, 112, 168, 224, 280].map((x) => (
          <line key={x} x1={x} y1="0" x2={x} y2="120" stroke="#1e293b" strokeWidth="1" />
        ))}
        <polyline
          fill="none"
          stroke="#38bdf8"
          strokeWidth="2"
          points="0,90 40,70 80,85 120,45 160,60 200,30 240,55 280,25"
        />
        {[0, 40, 80, 120, 160, 200, 240, 280].map((x, i) => (
          <circle
            key={x}
            cx={x}
            cy={[90, 70, 85, 45, 60, 30, 55, 25][i]}
            r="4"
            fill="#38bdf8"
          />
        ))}
      </svg>
      <div className="mt-2 flex justify-between px-1">
        {["Mon", "Tue", "Wed", "Thu", "Fri"].map((day) => (
          <span key={day} className="text-[10px] text-gray-500 md:text-xs">
            {day}
          </span>
        ))}
      </div>
    </div>
  )
}

function TradingHoursPlaceholder() {
  const bars = [72, 45, 88, 36, 64, 52, 78, 41]
  return (
    <div className="space-y-2 px-1">
      <p className="text-[11px] text-gray-400 md:text-sm">P&amp;L by hour</p>
      <div className="flex h-[100px] items-end justify-between gap-1 md:h-[120px]">
        {bars.map((h, i) => (
          <div
            key={i}
            className="flex-1 rounded-t bg-sky-500/40"
            style={{ height: `${h}%` }}
          />
        ))}
      </div>
      <div className="flex justify-between text-[10px] text-gray-500 md:text-xs">
        <span>Best hour</span>
        <span>Worst hour</span>
      </div>
    </div>
  )
}

function BehaviorWarningsPlaceholder() {
  const lines = [
    "Win rate drops after consecutive losses",
    "RR below 1.0 underperforms your average",
    "Late-session trades show higher drawdown",
  ]
  return (
    <div className="space-y-2.5">
      <p className="text-[11px] text-gray-400 md:text-sm">
        Post-loss streak &amp; RR comparisons
      </p>
      {lines.map((line) => (
        <p
          key={line}
          className="rounded-lg border border-amber-500/20 bg-amber-500/5 px-2.5 py-2 text-[11px] text-gray-300 md:text-sm"
        >
          🚨 {line}
        </p>
      ))}
    </div>
  )
}

function BestSetupPlaceholder() {
  const rows = [
    { label: "Strategy", width: "w-24" },
    { label: "Win rate", width: "w-16" },
    { label: "Total P&L", width: "w-20" },
    { label: "Trades", width: "w-10" },
  ]
  return (
    <div className="space-y-2.5">
      {rows.map(({ label, width }) => (
        <div key={label} className="flex items-center gap-2 text-[11px] md:text-sm">
          <span className="w-20 shrink-0 text-gray-400">{label}:</span>
          <span className={cn("h-3 rounded bg-white/15", width)} />
        </div>
      ))}
    </div>
  )
}

function AiAnalystPlaceholder() {
  return (
    <div className="space-y-3 px-1">
      <div className="ml-auto max-w-[85%] rounded-lg rounded-tr-sm bg-white/10 px-3 py-2">
        <p className="text-[11px] text-gray-300 md:text-sm">
          Why did my win rate drop this week?
        </p>
      </div>
      <div className="max-w-[90%] rounded-lg rounded-tl-sm border border-emerald-500/20 bg-emerald-500/5 px-3 py-2">
        <p className="text-[11px] leading-relaxed text-gray-400 md:text-sm">
          Your session timing and RR patterns suggest focusing on morning setups…
        </p>
      </div>
      <div className="flex gap-1.5">
        <span className="h-2 w-2 animate-pulse rounded-full bg-emerald-400/60" />
        <span className="h-2 w-16 rounded bg-white/10" />
      </div>
    </div>
  )
}

const PREVIEW_CARDS = [
  {
    title: "Session Performance",
    variant: "chart" as const,
    content: <SessionPerformancePlaceholder />,
  },
  {
    title: "Weekday Performance",
    variant: "chart" as const,
    content: <WeekdayPerformancePlaceholder />,
  },
  {
    title: "Trading Hours",
    variant: "insight" as const,
    content: <TradingHoursPlaceholder />,
  },
  {
    title: "Behavior Warnings",
    variant: "insight" as const,
    content: <BehaviorWarningsPlaceholder />,
  },
  {
    title: "Best Setup",
    variant: "insight" as const,
    content: <BestSetupPlaceholder />,
  },
  {
    title: "AI Analyst",
    variant: "insight" as const,
    content: <AiAnalystPlaceholder />,
  },
]

/** Premium widget previews at the bottom of the free dashboard. */
export default function DashboardPremiumPreviewSection({
  className = "",
}: DashboardPremiumPreviewSectionProps) {
  return (
    <section
      className={cn(
        "border-t border-white/10 pt-6 md:pt-8",
        className
      )}
      aria-labelledby="premium-dashboard-preview-title"
    >
      <div className="mb-4 md:mb-6">
        <h2
          id="premium-dashboard-preview-title"
          className="text-base font-semibold text-white md:text-lg"
        >
          🚀 Premium Dashboard Preview
        </h2>
        <p className="mt-1 text-sm text-gray-400">
          See everything available with TradeTraxs Pro.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 md:gap-6 lg:grid-cols-3">
        {PREVIEW_CARDS.map(({ title, variant, content }) => (
          <PreviewCard key={title} title={title} variant={variant}>
            {content}
          </PreviewCard>
        ))}
      </div>

      <div className="mt-5 flex justify-center md:mt-6">
        <Link
          href="/pricing"
          className={cn(
            buttonVariants({ variant: "primary", size: "md" }),
            "inline-flex w-full justify-center sm:w-auto"
          )}
        >
          Upgrade to Pro
        </Link>
      </div>
    </section>
  )
}
