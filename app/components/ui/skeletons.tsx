import type { ReactNode } from "react"
import Skeleton from "./Skeleton"
import { cn } from "./cn"

function SkeletonCard({
  children,
  className,
}: {
  children?: ReactNode
  className?: string
}) {
  return (
    <div
      className={cn(
        "rounded-xl border border-white/10 bg-white/5 p-4 backdrop-blur-md",
        className
      )}
    >
      {children}
    </div>
  )
}

export function SkeletonStatsCard({ className }: { className?: string }) {
  return (
    <SkeletonCard className={cn("p-4 text-center", className)}>
      <Skeleton className="mx-auto h-3 w-16" />
      <Skeleton className="mx-auto mt-2 h-6 w-20" />
    </SkeletonCard>
  )
}

export function SkeletonTradeCard({ className }: { className?: string }) {
  return (
    <SkeletonCard className={cn("space-y-3", className)}>
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0 flex-1 space-y-2">
          <Skeleton className="h-4 w-24" />
          <Skeleton className="h-3 w-32" />
        </div>
        <Skeleton className="h-5 w-16 shrink-0" />
      </div>
      <Skeleton className="h-3 w-full" />
      <Skeleton className="h-3 w-2/3" />
    </SkeletonCard>
  )
}

export function SkeletonProfileHeader({ className }: { className?: string }) {
  return (
    <SkeletonCard className={cn("p-6", className)}>
      <div className="flex flex-col items-center gap-4 sm:flex-row sm:items-start">
        <Skeleton className="h-20 w-20 shrink-0 rounded-full md:h-24 md:w-24" />
        <div className="min-w-0 flex-1 space-y-3">
          <Skeleton className="mx-auto h-6 w-40 sm:mx-0" />
          <Skeleton className="mx-auto h-4 w-28 sm:mx-0" />
          <Skeleton className="mx-auto h-4 w-48 sm:mx-0" />
          <Skeleton className="mx-auto h-16 w-full max-w-md sm:mx-0" />
        </div>
      </div>
    </SkeletonCard>
  )
}

export function SkeletonFeedPost({ className }: { className?: string }) {
  return (
    <SkeletonCard className={cn("space-y-3", className)}>
      <div className="flex items-center gap-3">
        <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
        <div className="min-w-0 flex-1 space-y-2">
          <Skeleton className="h-4 w-28" />
          <Skeleton className="h-3 w-20" />
        </div>
      </div>
      <Skeleton className="h-4 w-full" />
      <Skeleton className="h-4 w-4/5" />
      <Skeleton className="h-48 w-full rounded-lg" />
      <div className="flex gap-4 pt-1">
        <Skeleton className="h-4 w-12" />
        <Skeleton className="h-4 w-12" />
        <Skeleton className="h-4 w-12" />
      </div>
    </SkeletonCard>
  )
}

export function SkeletonComment({ className }: { className?: string }) {
  return (
    <div className={cn("flex items-start gap-2", className)}>
      <Skeleton className="h-8 w-8 shrink-0 rounded-full" />
      <div className="min-w-0 flex-1 space-y-2">
        <Skeleton className="h-3 w-20" />
        <Skeleton className="h-4 w-full max-w-sm" />
      </div>
    </div>
  )
}

export function SkeletonLeaderboardRow({ className }: { className?: string }) {
  return (
    <div className={cn("flex items-center gap-3 border-b border-white/10 py-3", className)}>
      <Skeleton className="h-5 w-8 shrink-0" />
      <Skeleton className="h-9 w-9 shrink-0 rounded-full" />
      <div className="min-w-0 flex-1 space-y-2">
        <Skeleton className="h-4 w-32" />
        <Skeleton className="h-3 w-20" />
      </div>
      <Skeleton className="h-4 w-16 shrink-0" />
      <Skeleton className="hidden h-4 w-12 shrink-0 sm:block" />
      <Skeleton className="hidden h-4 w-12 shrink-0 md:block" />
    </div>
  )
}

export function SkeletonMessage({ className }: { className?: string }) {
  return (
    <div className={cn("rounded-xl bg-white/5 p-3", className)}>
      <div className="mb-2 flex items-center gap-2">
        <Skeleton className="h-6 w-6 shrink-0 rounded-full" />
        <Skeleton className="h-4 w-24" />
        <Skeleton className="h-3 w-16" />
      </div>
      <Skeleton className="h-4 w-full max-w-md" />
      <Skeleton className="mt-2 h-4 w-2/3 max-w-sm" />
    </div>
  )
}

export function SkeletonNotificationRow({ className }: { className?: string }) {
  return (
    <div
      className={cn(
        "flex items-start gap-3 rounded-xl border border-white/10 bg-white/5 p-3",
        className
      )}
    >
      <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
      <div className="min-w-0 flex-1 space-y-2">
        <Skeleton className="h-4 w-full max-w-sm" />
        <Skeleton className="h-3 w-24" />
      </div>
    </div>
  )
}

export function SkeletonTraderCard({ className }: { className?: string }) {
  return (
    <SkeletonCard className={cn("flex items-center gap-3", className)}>
      <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
      <div className="min-w-0 flex-1 space-y-2">
        <Skeleton className="h-4 w-28" />
        <Skeleton className="h-3 w-20" />
        <Skeleton className="h-3 w-full max-w-xs" />
      </div>
    </SkeletonCard>
  )
}

export function SkeletonChart({ className }: { className?: string }) {
  return (
    <SkeletonCard className={cn("p-4", className)}>
      <Skeleton className="mb-3 h-4 w-32" />
      <Skeleton className="h-[280px] w-full rounded-lg md:h-[360px]" />
    </SkeletonCard>
  )
}

export function SkeletonTable({ rows = 5, className }: { rows?: number; className?: string }) {
  return (
    <SkeletonCard className={cn("space-y-3", className)}>
      <Skeleton className="h-4 w-40" />
      <div className="space-y-2">
        {Array.from({ length: rows }).map((_, i) => (
          <Skeleton key={i} className="h-10 w-full" />
        ))}
      </div>
    </SkeletonCard>
  )
}

export function SkeletonCalendarGrid({ className }: { className?: string }) {
  return (
    <div className={cn("space-y-3", className)}>
      <div className="grid grid-cols-7 gap-1 md:gap-2">
        {Array.from({ length: 7 }).map((_, i) => (
          <Skeleton key={`head-${i}`} className="aspect-square w-full rounded-lg" />
        ))}
      </div>
      <div className="grid grid-cols-7 gap-1 md:gap-2">
        {Array.from({ length: 35 }).map((_, i) => (
          <Skeleton key={`day-${i}`} className="aspect-square w-full rounded-lg" />
        ))}
      </div>
    </div>
  )
}

export function SkeletonChecklist({ className }: { className?: string }) {
  return (
    <SkeletonCard className={cn("space-y-3", className)}>
      <Skeleton className="h-5 w-48" />
      {Array.from({ length: 4 }).map((_, i) => (
        <div key={i} className="flex items-center gap-3">
          <Skeleton className="h-5 w-5 rounded" />
          <Skeleton className="h-4 flex-1 max-w-xs" />
        </div>
      ))}
    </SkeletonCard>
  )
}

export function SkeletonTradesFilterBar({ className }: { className?: string }) {
  return (
    <div
      className={cn(
        "flex flex-wrap items-center justify-center gap-2 md:justify-start md:gap-3",
        className
      )}
    >
      <Skeleton className="h-8 w-28 rounded-full" />
      <Skeleton className="h-8 w-28 rounded-full" />
      <Skeleton className="h-[34px] w-36 rounded-md" />
      <Skeleton className="h-[34px] w-32 rounded-md" />
      <Skeleton className="h-[34px] w-28 rounded-md" />
      <Skeleton className="h-[34px] w-24 rounded-md" />
      <Skeleton className="h-10 flex-1 rounded md:h-[34px] md:w-28 md:flex-none" />
      <Skeleton className="h-10 w-20 rounded md:h-[34px] md:w-24" />
      <Skeleton className="h-10 w-10 rounded md:h-[34px] md:w-10" />
    </div>
  )
}

export function SkeletonTradesPageTradeCard({ className }: { className?: string }) {
  return (
    <SkeletonCard
      className={cn(
        "px-2 py-3 md:px-4",
        className
      )}
    >
      <div className="flex flex-col gap-3 md:flex-row md:gap-2.5">
        <div className="min-w-0 flex-1 space-y-3">
          <div className="space-y-2 pr-16">
            <Skeleton className="h-5 w-36" />
            <Skeleton className="h-3 w-44" />
            <Skeleton className="h-3 w-32" />
          </div>
          <Skeleton className="h-8 w-24 rounded-lg" />
          <div className="flex flex-wrap gap-2">
            <Skeleton className="h-6 w-14 rounded" />
            <Skeleton className="h-6 w-14 rounded" />
          </div>
          <Skeleton className="h-3 w-28" />
          <Skeleton className="h-3 w-24" />
        </div>
        <Skeleton className="h-32 w-full shrink-0 rounded-lg md:h-28 md:w-36" />
      </div>
    </SkeletonCard>
  )
}

export function SkeletonTradesPageContent({ tradeCount = 6 }: { tradeCount?: number }) {
  return (
    <div aria-busy="true" aria-label="Loading trades">
      <div className="w-full mt-2.5 mb-1.5">
        <SkeletonTradesFilterBar />
      </div>

      <div className="w-full grid grid-cols-2 md:grid-cols-4 gap-2 mb-3 mt-0">
        {Array.from({ length: 4 }).map((_, i) => (
          <SkeletonStatsCard key={i} />
        ))}
      </div>

      <div className="w-full grid grid-cols-1 md:grid-cols-2 gap-4">
        {Array.from({ length: tradeCount }).map((_, i) => (
          <SkeletonTradesPageTradeCard key={i} />
        ))}
      </div>
    </div>
  )
}

export function SkeletonDashboardPage() {
  return (
    <div className="w-full px-3 pb-3 pt-0 text-white md:px-10 md:pb-10">
      <SkeletonDashboardShell />
    </div>
  )
}

/** Dashboard stats + charts placeholder — used while trades cache warms. */
export function SkeletonDashboardShell() {
  return (
    <div className="mx-auto flex w-full max-w-[1600px] flex-col gap-6 px-4 md:gap-8 md:px-6">
      <Skeleton className="h-4 w-24" />
      <div className="grid gap-4 overflow-visible lg:grid-cols-3 md:gap-6">
        <div className="grid grid-cols-2 gap-3 lg:col-span-1 md:grid-cols-3 lg:grid-cols-2">
          {Array.from({ length: 8 }).map((_, i) => (
            <SkeletonStatsCard key={i} />
          ))}
        </div>
        <div className="space-y-4 lg:col-span-2 md:space-y-6">
          <SkeletonChart />
          <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
            <SkeletonCard className="space-y-3">
              <Skeleton className="h-4 w-28" />
              {Array.from({ length: 3 }).map((_, i) => (
                <SkeletonTradeCard key={i} className="border-0 bg-black/20 p-3" />
              ))}
            </SkeletonCard>
            <SkeletonChart className="hidden md:block" />
          </div>
        </div>
      </div>
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3 md:gap-6">
        <SkeletonTable className="lg:col-span-2" />
        <SkeletonChart className="hidden md:block" />
      </div>
    </div>
  )
}

export function SkeletonAchievementsGrid({ count = 6 }: { count?: number }) {
  return (
    <div
      aria-busy="true"
      aria-label="Loading achievements"
      className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3"
    >
      {Array.from({ length: count }).map((_, i) => (
        <SkeletonTradeCard key={i} />
      ))}
    </div>
  )
}

export function SkeletonMessagesConversationList({ count = 6 }: { count?: number }) {
  return (
    <div aria-busy="true" aria-label="Loading conversations" className="space-y-2">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="flex items-center gap-3 rounded-lg p-3">
          <Skeleton className="h-12 w-12 shrink-0 rounded-full" />
          <div className="min-w-0 flex-1 space-y-2">
            <Skeleton className="h-4 w-32" />
            <Skeleton className="h-3 w-full max-w-xs" />
          </div>
        </div>
      ))}
    </div>
  )
}

export function SkeletonBacktestPageContent() {
  return (
    <div aria-busy="true" aria-label="Loading backtests" className="space-y-4">
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <SkeletonStatsCard key={i} />
        ))}
      </div>
      <SkeletonCard className="h-14" />
      <SkeletonChart />
      <SkeletonTable rows={4} />
    </div>
  )
}

export function SkeletonFeaturedTradesSection() {
  return (
    <section
      aria-busy="true"
      aria-label="Loading featured trades"
      className="relative z-10 border-t border-white/10 px-4 py-10 md:px-6 md:py-20"
    >
      <div className="mx-auto max-w-6xl space-y-6">
        <div className="mx-auto max-w-3xl space-y-3 text-center">
          <Skeleton className="mx-auto h-8 w-64" />
          <Skeleton className="mx-auto h-4 w-96 max-w-full" />
        </div>
        <div className="grid gap-4 md:grid-cols-2">
          <Skeleton className="min-h-[280px] w-full rounded-xl md:min-h-[320px]" />
          <Skeleton className="min-h-[280px] w-full rounded-xl md:min-h-[320px]" />
        </div>
      </div>
    </section>
  )
}

export function SkeletonTestimonialsSection() {
  return (
    <section
      aria-busy="true"
      aria-label="Loading testimonials"
      className="relative z-10 border-t border-white/10 px-4 py-10 md:px-6 md:py-20"
    >
      <div className="mx-auto max-w-6xl space-y-6">
        <div className="mx-auto max-w-3xl space-y-3 text-center">
          <Skeleton className="mx-auto h-8 w-72" />
          <Skeleton className="mx-auto h-4 w-80 max-w-full" />
        </div>
        <div className="grid gap-4 md:grid-cols-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <SkeletonCard key={i} className="min-h-[220px] md:min-h-[280px]" />
          ))}
        </div>
      </div>
    </section>
  )
}

export function SkeletonAnalystPanel({ count = 4 }: { count?: number }) {
  return (
    <div
      aria-busy="true"
      aria-label="Loading AI analyst"
      className="grid grid-cols-1 gap-8 lg:grid-cols-2"
    >
      <div className="max-h-[80vh] space-y-3 overflow-hidden rounded-xl border border-white/10 bg-white/5 p-4">
        {Array.from({ length: count }).map((_, i) => (
          <SkeletonTradeCard key={i} className="border-white/10" />
        ))}
      </div>
      <SkeletonCard className="min-h-[400px]">
        <Skeleton className="mb-4 h-5 w-40" />
        <div className="space-y-3">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-16 w-full rounded-lg" />
          ))}
        </div>
      </SkeletonCard>
    </div>
  )
}

export function SkeletonProfilePage() {
  return (
    <div className="w-full text-gray-100">
      <div className="mx-auto max-w-5xl space-y-4 px-4 py-6 sm:px-6 lg:px-8">
        <SkeletonProfileHeader />
        <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6 md:gap-4">
          {Array.from({ length: 6 }).map((_, i) => (
            <SkeletonStatsCard key={i} />
          ))}
        </div>
        <div className="flex justify-around border-b border-white/10 pb-2 sm:justify-start sm:gap-6">
          {Array.from({ length: 5 }).map((_, i) => (
            <Skeleton key={i} className="h-5 w-16" />
          ))}
        </div>
        <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
          {Array.from({ length: 4 }).map((_, i) => (
            <SkeletonTradeCard key={i} />
          ))}
        </div>
      </div>
    </div>
  )
}

export function SkeletonFeedPage({ count = 3 }: { count?: number }) {
  return (
    <div className="w-full space-y-6">
      <div className="flex justify-center gap-2">
        <Skeleton className="h-9 w-24 rounded-full" />
        <Skeleton className="h-9 w-24 rounded-full" />
      </div>
      <div className="flex gap-3 overflow-hidden">
        {Array.from({ length: 5 }).map((_, i) => (
          <Skeleton key={i} className="h-16 w-16 shrink-0 rounded-full" />
        ))}
      </div>
      {Array.from({ length: count }).map((_, i) => (
        <SkeletonFeedPost key={i} />
      ))}
    </div>
  )
}

export function SkeletonExplorePage() {
  return (
    <div className="mx-auto max-w-7xl space-y-8">
      <Skeleton className="h-10 w-full max-w-md rounded-xl" />
      <div className="space-y-4">
        <Skeleton className="h-5 w-32" />
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <SkeletonTraderCard key={i} />
          ))}
        </div>
      </div>
    </div>
  )
}

export function SkeletonLeaderboardPage() {
  return (
    <div className="mx-auto max-w-7xl space-y-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <Skeleton className="h-9 w-40" />
        <div className="flex gap-3">
          <Skeleton className="h-10 w-28" />
          <Skeleton className="h-10 w-36" />
        </div>
      </div>
      <SkeletonChart />
      <SkeletonCard className="space-y-1">
        <Skeleton className="mb-3 h-6 w-40" />
        {Array.from({ length: 8 }).map((_, i) => (
          <SkeletonLeaderboardRow key={i} />
        ))}
      </SkeletonCard>
    </div>
  )
}

export function SkeletonNotificationsPage() {
  return (
    <div className="mx-auto flex w-full max-w-xl flex-col gap-4">
      <div>
        <Skeleton className="h-3 w-16" />
        <Skeleton className="mt-2 h-8 w-48" />
        <Skeleton className="mt-2 h-4 w-full max-w-sm" />
      </div>
      <div className="flex gap-2">
        {Array.from({ length: 5 }).map((_, i) => (
          <Skeleton key={i} className="h-8 w-20 rounded-full" />
        ))}
      </div>
      {Array.from({ length: 5 }).map((_, i) => (
        <SkeletonNotificationRow key={i} />
      ))}
    </div>
  )
}

export function SkeletonCommunityPage() {
  return (
    <div className="grid min-h-[70vh] grid-cols-1 gap-4 md:grid-cols-[280px_1fr]">
      <SkeletonCard className="space-y-2 p-2">
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} className="flex items-center gap-3 px-2 py-2">
            <Skeleton className="h-8 w-8 rounded-full" />
            <Skeleton className="h-4 flex-1 max-w-[140px]" />
          </div>
        ))}
      </SkeletonCard>
      <SkeletonCard className="flex flex-col p-4">
        <Skeleton className="mb-4 h-6 w-40" />
        <div className="space-y-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <SkeletonMessage key={i} />
          ))}
        </div>
      </SkeletonCard>
    </div>
  )
}

export function SkeletonMessagesPage() {
  return (
    <div className="flex min-h-[60vh] flex-col">
      <div className="mb-4 flex items-center justify-between">
        <Skeleton className="h-8 w-32" />
        <div className="flex gap-2">
          <Skeleton className="h-9 w-24" />
          <Skeleton className="h-9 w-28" />
        </div>
      </div>
      <Skeleton className="mb-6 h-11 w-full rounded" />
      <div className="space-y-2">
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} className="flex items-center gap-3 rounded-lg p-3">
            <Skeleton className="h-12 w-12 shrink-0 rounded-full" />
            <div className="min-w-0 flex-1 space-y-2">
              <Skeleton className="h-4 w-32" />
              <Skeleton className="h-3 w-full max-w-xs" />
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

export function SkeletonCalendarPage() {
  return (
    <div className="mx-auto grid w-full max-w-7xl grid-cols-1 items-start gap-4 px-4 md:grid-cols-[2fr_1.4fr] md:gap-8">
      <div className="w-full min-w-0">
        <div className="mb-6 flex items-center justify-between">
          <Skeleton className="h-8 w-8" />
          <Skeleton className="h-8 w-40" />
          <Skeleton className="h-8 w-8" />
        </div>
        <div className="mb-4 flex gap-3">
          <Skeleton className="h-10 flex-1 max-w-xs" />
          <Skeleton className="h-10 w-28" />
        </div>
        <SkeletonCalendarGrid />
      </div>
      <SkeletonCard className="space-y-3">
        <Skeleton className="h-5 w-32" />
        {Array.from({ length: 4 }).map((_, i) => (
          <SkeletonTradeCard key={i} className="border-0 bg-black/20 p-3" />
        ))}
      </SkeletonCard>
    </div>
  )
}

export function SkeletonSettingsPage() {
  return (
    <div className="mx-auto flex max-w-6xl flex-col gap-6 md:flex-row md:items-start">
      <aside className="w-full shrink-0 md:w-64">
        <Skeleton className="mb-2 h-8 w-28" />
        <Skeleton className="mb-4 h-4 w-20" />
        <div className="flex flex-row gap-2 md:flex-col md:gap-1">
          {Array.from({ length: 5 }).map((_, i) => (
            <Skeleton key={i} className="h-14 w-full rounded-xl" />
          ))}
        </div>
      </aside>
      <div className="min-w-0 flex-1 space-y-6">
        <div>
          <Skeleton className="h-6 w-32" />
          <Skeleton className="mt-2 h-4 w-64" />
        </div>
        <SkeletonCard className="space-y-6 p-6">
          <div className="flex items-center gap-4">
            <Skeleton className="h-16 w-16 rounded-full" />
            <Skeleton className="h-10 w-40" />
          </div>
          {Array.from({ length: 4 }).map((_, i) => (
            <div key={i} className="space-y-2">
              <Skeleton className="h-4 w-24" />
              <Skeleton className="h-12 w-full rounded-xl" />
            </div>
          ))}
        </SkeletonCard>
      </div>
    </div>
  )
}

export function SkeletonAnalyticsPage() {
  return (
    <div className="space-y-6 md:space-y-8">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <SkeletonStatsCard key={i} />
        ))}
      </div>
      <SkeletonChart />
      <SkeletonTable rows={6} />
    </div>
  )
}

function SkeletonAffiliateStatCard({ className }: { className?: string }) {
  return (
    <SkeletonCard className={cn("p-5", className)}>
      <Skeleton className="h-4 w-28" />
      <Skeleton className="mt-3 h-8 w-14" />
      <Skeleton className="mt-3 h-3 w-full" />
    </SkeletonCard>
  )
}

function SkeletonAffiliateReferralRow({ className }: { className?: string }) {
  return (
    <SkeletonCard className={cn("p-4", className)}>
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex min-w-0 items-center gap-3">
          <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
          <div className="min-w-0 space-y-2">
            <Skeleton className="h-4 w-28" />
            <Skeleton className="h-3 w-24" />
          </div>
        </div>
        <div className="flex flex-wrap items-center gap-3 sm:justify-end">
          <Skeleton className="h-6 w-16 rounded-full" />
          <Skeleton className="h-8 w-24" />
        </div>
      </div>
    </SkeletonCard>
  )
}

export function SkeletonAffiliateDashboardPage() {
  return (
    <div aria-busy="true" aria-label="Loading affiliate dashboard" className="space-y-8">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <Skeleton className="h-9 w-52 sm:w-64" />
        <div className="flex items-center gap-2">
          <Skeleton className="h-10 w-24 rounded-lg" />
          <Skeleton className="h-10 w-20 rounded-lg" />
        </div>
      </div>

      <Skeleton className="h-14 w-full rounded-xl" />

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        {Array.from({ length: 3 }).map((_, i) => (
          <SkeletonAffiliateStatCard key={`summary-${i}`} />
        ))}
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        {Array.from({ length: 3 }).map((_, i) => (
          <SkeletonAffiliateStatCard key={`lifecycle-${i}`} />
        ))}
      </div>

      <SkeletonCard className="space-y-3 p-4">
        <Skeleton className="h-3 w-36" />
        <Skeleton className="h-4 w-48" />
        <Skeleton className="h-10 w-44 rounded-lg" />
      </SkeletonCard>

      <SkeletonCard className="space-y-4 p-6">
        <Skeleton className="h-4 w-28" />
        <Skeleton className="h-5 w-24" />
        <Skeleton className="h-4 w-20" />
        <Skeleton className="h-10 w-full rounded-lg" />
        <div className="flex flex-col gap-2 sm:flex-row">
          <Skeleton className="h-10 min-w-0 flex-1 rounded-lg" />
          <Skeleton className="h-10 w-28 shrink-0 rounded-lg" />
        </div>
      </SkeletonCard>

      <div>
        <Skeleton className="mb-4 h-6 w-32" />
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <SkeletonAffiliateReferralRow key={i} />
          ))}
        </div>
      </div>
    </div>
  )
}

export function SkeletonAffiliateOnboardingPage() {
  return (
    <div aria-busy="true" aria-label="Loading affiliate program" className="space-y-8">
      <div className="space-y-2">
        <Skeleton className="h-9 w-56" />
        <Skeleton className="h-4 w-full max-w-2xl" />
      </div>
      <SkeletonCard className="space-y-4 p-6 sm:p-8">
        <Skeleton className="h-6 w-64" />
        <Skeleton className="h-4 w-full" />
        <Skeleton className="h-4 w-5/6" />
        <div className="space-y-2 pt-2">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-4 w-full max-w-md" />
          ))}
        </div>
        <Skeleton className="h-20 w-full rounded-lg" />
        <Skeleton className="h-11 w-44 rounded-lg" />
      </SkeletonCard>
      <SkeletonCard className="p-6 sm:p-8">
        <div className="flex items-start gap-4">
          <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
          <div className="min-w-0 flex-1 space-y-2">
            <Skeleton className="h-5 w-40" />
            <Skeleton className="h-4 w-full max-w-lg" />
          </div>
        </div>
      </SkeletonCard>
    </div>
  )
}

export function SkeletonPayoutsPage() {
  return (
    <div aria-busy="true" aria-label="Loading payouts" className="space-y-6">
      <Skeleton className="h-14 w-full rounded-xl" />

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <SkeletonAffiliateStatCard key={i} />
        ))}
      </div>

      <SkeletonCard className="space-y-3 p-4">
        <Skeleton className="h-3 w-36" />
        <Skeleton className="h-4 w-48" />
        <Skeleton className="h-10 w-44 rounded-lg" />
      </SkeletonCard>

      <Skeleton className="h-11 w-36 rounded-lg" />

      <div className="space-y-3">
        <Skeleton className="h-4 w-24" />
        <SkeletonCard className="h-24" />
      </div>
    </div>
  )
}

export { SkeletonCard }
