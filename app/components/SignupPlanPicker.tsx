"use client"

import TraxProBillingIntervalPicker from "@/app/components/TraxProBillingIntervalPicker"
import { TRAXPRO_TRIAL_HEADLINE } from "@/lib/traxProPricing"
import {
  TRADETRAXS_FREE_PLAN,
  TRADETRAXS_PRO_PLAN,
} from "@/lib/tradeTraxsPlans"
import type { TraxProBillingIntervalId } from "@/lib/traxProBillingPlans"

import type { SignupIntent } from "@/lib/signupFlow"

export type SignupPlanPickerProps = {
  billingInterval: TraxProBillingIntervalId
  onBillingIntervalChange: (interval: TraxProBillingIntervalId) => void
  onSelectTrial: () => void
  onSelectFree: () => void
  selectedIntent?: SignupIntent | null
  onSelectIntent?: (intent: SignupIntent) => void
  disabled?: boolean
  loading?: boolean
  trialButtonLabel?: string
  freeButtonLabel?: string
  billingPickerName?: string
}

/** Shared Free vs Pro trial plan cards — login signup and post-Google-auth choose-plan. */
export default function SignupPlanPicker({
  billingInterval,
  onBillingIntervalChange,
  onSelectTrial,
  onSelectFree,
  selectedIntent = null,
  onSelectIntent,
  disabled = false,
  loading = false,
  trialButtonLabel = "Start Free Trial",
  freeButtonLabel = "Continue Free",
  billingPickerName = "signup-plan-billing",
}: SignupPlanPickerProps) {
  const controlsDisabled = disabled || loading

  return (
    <div className="space-y-3 md:space-y-2.5">
      <div
        role="button"
        tabIndex={controlsDisabled ? -1 : 0}
        onClick={() => {
          if (controlsDisabled) return
          onSelectIntent?.("trial")
        }}
        onKeyDown={(event) => {
          if (controlsDisabled) return
          if (event.key === "Enter" || event.key === " ") {
            event.preventDefault()
            onSelectIntent?.("trial")
          }
        }}
        className={`relative rounded-xl border bg-gradient-to-b from-emerald-500/10 to-white/[0.04] p-4 transition md:p-3 ${
          selectedIntent === "trial"
            ? "border-blue-400/70 ring-1 ring-blue-400/40"
            : "border-emerald-400/40"
        } ${controlsDisabled ? "" : "cursor-pointer"}`}
      >
        <span className="absolute -top-2.5 right-3 rounded-full bg-emerald-500 px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-white">
          Recommended
        </span>
        <p className="text-sm font-semibold text-white">
          ⭐ Start {TRAXPRO_TRIAL_HEADLINE}
        </p>
        <p className="mt-1 text-xs leading-relaxed text-gray-400 md:text-[11px]">
          {TRADETRAXS_PRO_PLAN.description}
        </p>
        <div className="mt-3">
          <TraxProBillingIntervalPicker
            value={billingInterval}
            onChange={onBillingIntervalChange}
            disabled={controlsDisabled}
            name={billingPickerName}
          />
        </div>
        <button
          type="button"
          disabled={controlsDisabled}
          onClick={(event) => {
            event.stopPropagation()
            onSelectIntent?.("trial")
            onSelectTrial()
          }}
          className="mt-4 w-full rounded-xl bg-blue-500 py-3 text-sm font-semibold text-white transition hover:bg-blue-600 hover:scale-[1.02] disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:bg-blue-500 disabled:hover:scale-100 md:mt-3 md:py-2.5"
        >
          {loading ? "Loading..." : trialButtonLabel}
        </button>
      </div>

      <div
        role="button"
        tabIndex={controlsDisabled ? -1 : 0}
        onClick={() => {
          if (controlsDisabled) return
          onSelectIntent?.("free")
        }}
        onKeyDown={(event) => {
          if (controlsDisabled) return
          if (event.key === "Enter" || event.key === " ") {
            event.preventDefault()
            onSelectIntent?.("free")
          }
        }}
        className={`rounded-xl border bg-white/[0.04] p-4 transition md:p-3 ${
          selectedIntent === "free"
            ? "border-blue-400/50 ring-1 ring-blue-400/30"
            : "border-white/10"
        } ${controlsDisabled ? "" : "cursor-pointer"}`}
      >
        <p className="text-sm font-semibold text-white">{TRADETRAXS_FREE_PLAN.name}</p>
        <p className="mt-1 text-xs leading-relaxed text-gray-400 md:text-[11px]">
          {TRADETRAXS_FREE_PLAN.description}
        </p>
        <button
          type="button"
          disabled={controlsDisabled}
          onClick={(event) => {
            event.stopPropagation()
            onSelectIntent?.("free")
            onSelectFree()
          }}
          className="mt-4 w-full rounded-xl border border-white/15 bg-white/[0.06] py-3 text-sm font-semibold text-white transition hover:border-white/25 hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-60 md:mt-3 md:py-2.5"
        >
          {loading ? "Loading..." : freeButtonLabel}
        </button>
      </div>
    </div>
  )
}
