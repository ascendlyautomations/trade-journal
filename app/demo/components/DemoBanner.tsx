"use client"

import Link from "next/link"
import { shouldShowCustomerHomeChrome } from "@/lib/marketingAccess"
import { TRAXPRO_TRIAL_HEADLINE } from "@/lib/traxProPricing"
import { enterSignupFlow } from "@/lib/signupFlow"
import { useUserProfile } from "@/lib/useUserProfile"

export default function DemoBanner() {
  const { user, profile, loading } = useUserProfile()
  const showTrialCta = !shouldShowCustomerHomeChrome(user, profile, loading)

  return (
    <div
      className="fixed left-0 right-0 top-[var(--navbar-height)] z-[9998] flex h-10 items-center border-b border-emerald-500/25 bg-gradient-to-r from-[#0c2a45]/95 via-[#0b1f3a]/95 to-[#0a2238]/95 shadow-sm backdrop-blur-sm sm:h-14"
      role="status"
      aria-live="polite"
    >
      <div className="mx-auto flex h-full w-full max-w-6xl items-center justify-between gap-3 px-4 sm:px-6">
        <p className="min-w-0 text-xs text-gray-200 sm:text-sm">
          <span className="font-medium text-white sm:hidden">
            You&apos;re exploring TradeTraxs Demo.
          </span>
          <span className="hidden sm:inline">
            <span className="font-medium text-white">
              You&apos;re exploring the TradeTraxs Demo.
            </span>{" "}
            Create your own account to start tracking your trading journey.
          </span>
        </p>
        {showTrialCta ? (
          <Link
            href="/login?tab=signup"
            onClick={() => enterSignupFlow()}
            className="hidden shrink-0 rounded-lg bg-emerald-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-emerald-600 sm:inline-flex"
          >
            Start {TRAXPRO_TRIAL_HEADLINE}
          </Link>
        ) : null}
      </div>
    </div>
  )
}
