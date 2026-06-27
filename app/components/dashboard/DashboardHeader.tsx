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
    <div className={`shrink-0 text-sm text-white/70 ${className}`}>
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
    <>
      {showFreePlanAccountBanner ? (
        <div className="mb-4 rounded border border-yellow-500/20 bg-yellow-500/10 p-3 md:p-4">
          <p className="text-xs md:text-sm text-yellow-300">
            Free plan: up to 3 accounts. Upgrade for unlimited accounts.
          </p>
        </div>
      ) : null}
    </>
  )
}
