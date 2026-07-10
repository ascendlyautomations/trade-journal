"use client"

import {
  getTraxProBillingPlan,
  TRAXPRO_BILLING_PLANS,
  TRAXPRO_DEFAULT_BILLING_INTERVAL,
  type TraxProBillingIntervalId,
} from "@/lib/traxProBillingPlans"

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
  return (
    <fieldset
      className={`space-y-2 ${className}`}
      disabled={disabled}
      aria-label="Choose billing interval"
    >
      {TRAXPRO_BILLING_PLANS.map((plan) => {
        const checked = value === plan.id
        const inputId = `${name}-${plan.id}`
        return (
          <label
            key={plan.id}
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
              value={plan.id}
              checked={checked}
              onChange={() => onChange(plan.id)}
              className="mt-0.5 h-4 w-4 shrink-0 border-white/20 bg-white/10 text-blue-500 focus:ring-2 focus:ring-blue-400 focus:ring-offset-0"
            />
            <span className="text-sm leading-snug text-gray-200">
              {plan.checkoutOptionLabel}
            </span>
          </label>
        )
      })}
    </fieldset>
  )
}

export { TRAXPRO_DEFAULT_BILLING_INTERVAL, getTraxProBillingPlan }
