"use client"

import type { TraxProBillingIntervalId } from "@/lib/traxProBillingPlans"
import { useTraxProPriceCatalog } from "@/lib/traxProPriceCatalogClient"

type Props = {
  interval: TraxProBillingIntervalId
  className?: string
  variant?: "full" | "compact"
}

export default function TraxProSelectedPlanPrice({
  interval,
  className = "",
  variant = "full",
}: Props) {
  const { status, plan, errorMessage, refresh } = useTraxProPriceCatalog()
  const selected = interval === "test" ? null : plan(interval)

  if (status === "idle" || status === "loading") {
    return <p className={`text-sm text-gray-300 ${className}`}>Loading plans…</p>
  }

  if (status === "error" || !selected) {
    return (
      <div className={className}>
        <p className="text-sm text-gray-300">
          {errorMessage ?? "Couldn't load this Stripe price."}
        </p>
        <button
          type="button"
          onClick={() => void refresh()}
          className="mt-2 text-sm font-semibold text-blue-300 hover:text-blue-200"
        >
          Try again
        </button>
      </div>
    )
  }

  if (variant === "compact") {
    return (
      <p className={`text-sm font-medium text-gray-300 ${className}`}>
        {selected.totalLabel} · {selected.billingCadenceLabel}
      </p>
    )
  }

  return (
    <div className={className}>
      {selected.aligned && selected.savePercent != null ? (
        <p className="text-sm font-semibold text-emerald-300">
          Save {selected.savePercent}%
        </p>
      ) : null}
      <p className="mt-2 text-4xl font-bold tracking-tight sm:text-5xl">
        {selected.totalLabel}
      </p>
      <p className="mt-1 text-sm font-medium text-gray-300">
        {selected.equivalentMonthlyLabel
          ? `${selected.equivalentMonthlyLabel} · ${selected.billingCadenceLabel}`
          : selected.billingCadenceLabel}
      </p>
    </div>
  )
}
