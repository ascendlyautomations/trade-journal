"use client"

export type DashboardHeaderProps = {
  showFreePlanAccountBanner: boolean
}

export type DashboardPlanIndicatorProps = {
  isPro: boolean
  className?: string
}

export function DashboardPlanIndicator({
  isPro,
  className = "",
}: DashboardPlanIndicatorProps) {
  return (
    <div className={`shrink-0 text-xs text-white/70 md:text-sm ${className}`}>
      Plan:{" "}
      <span
        className={`font-medium ${isPro ? "text-green-400" : "text-gray-300"}`}
      >
        {isPro ? "Pro" : "Free"}
      </span>
    </div>
  )
}

export default function DashboardHeader({
  showFreePlanAccountBanner,
}: DashboardHeaderProps) {
  return (
    <h1 className="sr-only">Dashboard</h1>
  )
}
