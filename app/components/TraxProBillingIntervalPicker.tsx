"use client"

import { useEffect } from "react"
import {
  TRAXPRO_DEFAULT_BILLING_INTERVAL,
  getTraxProBillingPlan,
  getVisibleTraxProBillingPlans,
  type TraxProBillingIntervalId,
} from "@/lib/traxProBillingPlans"
import { useTraxProPriceCatalog } from "@/lib/traxProPriceCatalogClient"

type Props = {
  value: TraxProBillingIntervalId
  onChange: (interval: TraxProBillingIntervalId) => void
  disabled?: boolean
  name?: string
  className?: string
}

export default function TraxProBillingIntervalPicker({
  value,
  onChange,
  disabled = false,
  name = "traxpro-billing-interval",
  className = "",
}: Props) {
  const { status, plan, catalog, errorMessage, refresh } = useTraxProPriceCatalog()
  const plans = getVisibleTraxProBillingPlans()

  useEffect(() => {
    if (status !== "ready") return
    if (plan(value)) return
    const first = plans.find((item) => plan(item.id))
    if (first) onChange(first.id)
  }, [onChange, plan, plans, status, value])

  if (status === "idle" || status === "loading") {
    return <p className={`text-sm text-gray-300 ${className}`}>Loading plans…</p>
  }

  if (status === "error") {
    return (
      <div className={className}>
        <p className="text-sm text-gray-300">{errorMessage}</p>
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

  return (
    <fieldset
      className={`space-y-2 ${className}`}
      disabled={disabled}
      aria-label="Choose billing interval"
    >
      {catalog?.unavailable.length ? (
        <p className="text-xs leading-relaxed text-gray-400">
          {catalog.unavailable
            .map((interval) => (interval === "six_month" ? "6 months" : interval === "yearly" ? "Yearly" : "Monthly"))
            .join(", ")}{" "}
          {catalog.unavailable.length === 1 ? "price isn't" : "prices aren't"} available from Stripe.
        </p>
      ) : null}
      {plans.map((fallback) => {
        const live = plan(fallback.id)
        if (!live) return null
        const checked = value === fallback.id
        const inputId = `${name}-${fallback.id}`
        return (
          <label
            key={fallback.id}
            htmlFor={inputId}
            className={`flex cursor-pointer items-start gap-3 rounded-lg border px-3 py-2.5 text-left transition ${
              checked
                ? "border-blue-400/40 bg-blue-500/10"
                : "border-white/10 bg-white/[0.03] hover:border-white/20"
            } ${disabled ? "cursor-not-allowed opacity-60" : ""}`}
          >
            <input
              id={inputId}
              type="radio"
              name={name}
              value={fallback.id}
              checked={checked}
              onChange={() => onChange(fallback.id)}
              className="mt-0.5 h-4 w-4 shrink-0 border-white/20 bg-white/10 text-blue-500 focus:ring-2 focus:ring-blue-400 focus:ring-offset-0"
            />
            <span className="min-w-0 text-sm leading-snug text-gray-200">
              <span className="font-medium text-white">{live.checkoutOptionLabel}</span>
              <span className="mt-0.5 block text-xs text-gray-400">
                {live.totalLabel}
                {live.equivalentMonthlyLabel && (live.monthsInCycle ?? 0) > 1
                  ? ` · ${live.equivalentMonthlyLabel}`
                  : ""}
              </span>
            </span>
          </label>
        )
      })}
    </fieldset>
  )
}

export { TRAXPRO_DEFAULT_BILLING_INTERVAL, getTraxProBillingPlan }
