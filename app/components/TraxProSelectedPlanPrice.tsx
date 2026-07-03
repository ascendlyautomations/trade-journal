"use client"

import {
  formatTraxProEffectiveMonthly,
  getTraxProBillingPlan,
  type TraxProBillingIntervalId,
} from "@/lib/traxProBillingPlans"
import { TRAXPRO_PRICE_STARTING_AT } from "@/lib/traxProPricing"

type Props = {
  interval: TraxProBillingIntervalId
  className?: string
  /** Show save badge + cadence (pricing page). Hide on compact cards. */
  variant?: "full" | "compact"
}

export default function TraxProSelectedPlanPrice({
  interval,
  className = "",
  variant = "full",
}: Props) {
  const plan = getTraxProBillingPlan(interval)

  if (variant === "compact") {
    return (
      <div className={className}>
        <p className="mt-2 text-sm font-medium text-gray-400">{TRAXPRO_PRICE_STARTING_AT}</p>
      </div>
    )
  }

  return (
    <div className={className}>
      {plan.bestValue ? (
        <p className="text-xs font-semibold uppercase tracking-wide text-amber-300">
          ⭐ Best Value
        </p>
      ) : null}
      {plan.savePercent != null ? (
        <p className={`text-sm font-semibold text-emerald-300 ${plan.bestValue ? "mt-1" : ""}`}>
          Save {plan.savePercent}%
        </p>
      ) : null}
      <p className="mt-2 text-4xl font-bold tracking-tight sm:text-5xl">
        {formatTraxProEffectiveMonthly(plan)}
      </p>
      <p className="mt-1 text-sm font-medium text-gray-300">{plan.billingCadenceLabel}</p>
    </div>
  )
}
