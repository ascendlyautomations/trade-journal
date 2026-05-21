"use client"

export type DashboardHeaderProps = {
  isPro: boolean
  showFreePlanAccountBanner: boolean
}

export default function DashboardHeader({
  isPro,
  showFreePlanAccountBanner,
}: DashboardHeaderProps) {
  return (
    <>
      <div className="mt-1 mb-2 text-left text-sm text-white/60">
        Plan:{" "}
        <span
          className={`font-medium ${isPro ? "text-green-400" : "text-gray-400"}`}
        >
          {isPro ? "Pro" : "Free"}
        </span>
      </div>

      {showFreePlanAccountBanner ? (
        <div className="mb-4 rounded border border-yellow-500/20 bg-yellow-500/10 p-3 md:p-4">
          <p className="text-xs md:text-sm text-yellow-300">
            Free plan: 1 account limit. Upgrade for unlimited accounts.
          </p>
        </div>
      ) : null}
    </>
  )
}
