"use client"

import type { ReactNode } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import TradingScorecardDetailView from "@/app/components/scorecard/TradingScorecardDetailView"
import { scorecardPanelClass, scorecardSubtitleClass, scorecardTitleClass } from "@/app/components/scorecard/scorecardStyles"
import { AUTH_PAGE_CONTAINER_CLASS } from "@/lib/authenticatedPageShell"
import { useScorecardPageHydration } from "@/lib/scorecard/useScorecardPageHydration"
import { MOBILE_WEB_NEUTRAL_PAGE_BG } from "@/lib/mobileWebPageSurface"
import { useScrollPageTopOnMount } from "@/lib/useScrollPageTopOnMount"
import { useUserProfile } from "@/lib/useUserProfile"
import { useProGate } from "@/lib/useProGate"

export default function TradingScorecardPage() {
  useScrollPageTopOnMount()
  const router = useRouter()
  const { user, profile } = useUserProfile()
  const { proFeatureUnlocked } = useProGate(profile)
  const hydration = useScorecardPageHydration(user?.id)

  const shell = (children: ReactNode) => (
    <div className={`${MOBILE_WEB_NEUTRAL_PAGE_BG} min-h-screen pb-12 pt-6 text-white`}>
      <div className={AUTH_PAGE_CONTAINER_CLASS}>
        <button
          type="button"
          onClick={() => router.push("/dashboard")}
          className="mb-4 text-sm text-blue-400 hover:underline"
        >
          ← Dashboard
        </button>
        {children}
      </div>
    </div>
  )

  if (hydration.status === "loading" && !hydration.result) {
    return shell(
      <section className={scorecardPanelClass} data-testid="scorecard.page.loading">
        <h1 className={scorecardTitleClass}>Trading Scorecard</h1>
        <p className={`mt-2 ${scorecardSubtitleClass}`}>
          Loading trades and check-ins for your dashboard scope…
        </p>
        <div className="mt-4 h-2 w-48 animate-pulse rounded-full bg-white/10" />
      </section>
    )
  }

  if (hydration.status === "loading" && hydration.result) {
    return shell(
      <>
        <p className="mb-3 text-xs text-gray-500" data-testid="scorecard.page.updating">
          Updating scorecard for {hydration.scopeLabel}…
        </p>
        <TradingScorecardDetailView
          result={hydration.result}
          proFeatureUnlocked={proFeatureUnlocked}
        />
      </>
    )
  }

  if (hydration.status === "error") {
    return shell(
      <section className={scorecardPanelClass} data-testid="scorecard.page.error">
        <h1 className={scorecardTitleClass}>Trading Scorecard</h1>
        <p className="mt-2 text-sm text-red-400">
          {hydration.errorMessage ?? "Could not load scorecard data."}
        </p>
        <Link
          href="/dashboard"
          className="mt-4 inline-block text-sm font-semibold text-blue-400 hover:underline"
        >
          Return to Dashboard
        </Link>
      </section>
    )
  }

  if (hydration.status === "empty") {
    return shell(
      <section className={scorecardPanelClass} data-testid="scorecard.page.empty">
        <h1 className={scorecardTitleClass}>Trading Scorecard</h1>
        <p className={`mt-2 ${scorecardSubtitleClass}`}>
          No trades match your current dashboard filters ({hydration.scopeLabel}). Adjust filters
          on the dashboard or log trades to build a score.
        </p>
        <Link
          href="/dashboard"
          className="mt-4 inline-block text-sm font-semibold text-blue-400 hover:underline"
        >
          Go to Dashboard
        </Link>
      </section>
    )
  }

  if (!hydration.result) {
    return shell(
      <section className={scorecardPanelClass} data-testid="scorecard.page.unavailable">
        <h1 className={scorecardTitleClass}>Trading Scorecard</h1>
        <p className={`mt-2 ${scorecardSubtitleClass}`}>
          Scorecard data is not available yet. Open the dashboard to load your journal, then try
          again.
        </p>
        <Link
          href="/dashboard"
          className="mt-4 inline-block text-sm font-semibold text-blue-400 hover:underline"
        >
          Go to Dashboard
        </Link>
      </section>
    )
  }

  return shell(
    <>
      {hydration.errorMessage ? (
        <p className="mb-3 text-xs text-amber-400/90" role="status">
          Some journal data could not be refreshed: {hydration.errorMessage}
        </p>
      ) : null}
      {hydration.usingCachedSnapshot ? (
        <p className="mb-3 text-xs text-gray-500" data-testid="scorecard.page.cached">
          Showing saved breakdown — refreshing live data…
        </p>
      ) : null}
      <TradingScorecardDetailView
        result={hydration.result}
        proFeatureUnlocked={proFeatureUnlocked}
      />
    </>
  )
}
