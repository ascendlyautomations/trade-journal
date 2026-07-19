"use client"

import { useCallback, useEffect, useState } from "react"
import { usePathname } from "next/navigation"
import GettingStartedChecklist from "@/app/components/dashboard/GettingStartedChecklist"
import TraxsProForLifeCard from "@/app/components/dashboard/TraxsProForLifeCard"
import ModalCloseButton from "@/app/components/ui/ModalCloseButton"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import { useGettingStartedProgress } from "@/lib/GettingStartedProgressProvider"
import { shouldOfferGettingStartedChecklist } from "@/lib/gettingStartedChecklist"
import { shouldShowProForLifeCard } from "@/lib/earlyAccess"
import { useEarlyAccessChallengeProgress } from "@/lib/useEarlyAccessChallengeProgress"
import { auditLogNavbarDecision } from "@/lib/onboardingChecklistAudit"
import { useUserProfile } from "@/lib/useUserProfile"

const FOUNDING_CHALLENGE_TASK_COUNT = 3

type GettingStartedMobileEntryProps = {
  /**
   * `menu` — large item inside the mobile slide-out nav.
   * `header` — compact chip (legacy mobile header).
   * `desktop-nav` — compact chip between notifications and profile.
   */
  placement?: "header" | "menu" | "desktop-nav"
}

export default function GettingStartedMobileEntry({
  placement = "header",
}: GettingStartedMobileEntryProps) {
  const pathname = usePathname()
  const { user, profile, refreshProfile } = useUserProfile()
  const {
    progress,
    signals,
    signalsReady,
    refreshChecklistSignals,
  } = useGettingStartedProgress()

  // Early Access users get a combined Getting Started + Founding Challenge
  // total. Eligibility reuses the exact dashboard card rule.
  const foundingChallengeEligible =
    Boolean(user?.id) && shouldShowProForLifeCard(profile)
  const { progress: challengeProgress } = useEarlyAccessChallengeProgress(
    foundingChallengeEligible
  )
  const challengeCompletedCount = foundingChallengeEligible
    ? Math.min(
        challengeProgress?.completedCount ?? 0,
        FOUNDING_CHALLENGE_TASK_COUNT
      )
    : 0

  const [drawerOpen, setDrawerOpen] = useState(false)

  const tradeTaskComplete = progress.items.some(
    (item) => item.id === "trade" && item.complete
  )
  const hasFirstTrade = signals.tradeCount > 0 || tradeTaskComplete

  const combinedAllComplete =
    progress.allComplete &&
    (!foundingChallengeEligible ||
      challengeCompletedCount >= FOUNDING_CHALLENGE_TASK_COUNT)

  // Desktop + mobile share the same completion gate.
  const canOffer =
    signalsReady &&
    shouldOfferGettingStartedChecklist(user?.id, {
      allComplete: combinedAllComplete,
      hasSeenOnboardingCompletePopup: signals.hasSeenOnboardingCompletePopup,
    })

  // Always visible until every combined task is complete (no first-trade gate).
  const visible = canOffer

  useEffect(() => {
    if (!user?.id) return
    const reason = !signalsReady
      ? "signals not ready"
      : combinedAllComplete
        ? "all tasks complete"
        : visible
          ? "show navbar onboarding"
          : "hidden"
    auditLogNavbarDecision({
      placement,
      visible,
      reason,
      signalsReady,
      tradeCount: signals.tradeCount,
      completedCount: progress.completedCount,
      totalCount: progress.totalCount,
      allComplete: progress.allComplete,
      hasSeenOnboardingCompletePopup: signals.hasSeenOnboardingCompletePopup,
      hasFirstTrade,
    })
  }, [
    user?.id,
    placement,
    visible,
    signalsReady,
    signals.tradeCount,
    signals.hasSeenOnboardingCompletePopup,
    progress.completedCount,
    progress.totalCount,
    progress.allComplete,
    combinedAllComplete,
    hasFirstTrade,
  ])

  const closeDrawer = useCallback(() => {
    setDrawerOpen(false)
  }, [])

  useEffect(() => {
    closeDrawer()
  }, [pathname, closeDrawer])

  useEffect(() => {
    if (!drawerOpen) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") closeDrawer()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [drawerOpen, closeDrawer])

  useModalScrollLock(drawerOpen)

  if (!visible || !user?.id) return null

  const completedCount =
    progress.completedCount + challengeCompletedCount
  const totalCount =
    progress.totalCount +
    (foundingChallengeEligible ? FOUNDING_CHALLENGE_TASK_COUNT : 0)
  const buttonTitle = foundingChallengeEligible
    ? "Getting Started"
    : placement === "desktop-nav"
      ? "Onboarding"
      : "Complete Onboarding"
  const drawerTitle = foundingChallengeEligible
    ? "Getting Started"
    : "Complete Onboarding"
  const countLabel = `(${completedCount}/${totalCount})`
  const ariaLabel = `${drawerTitle}, ${completedCount} of ${totalCount} tasks done`

  const openButton =
    placement === "menu" ? (
      <button
        type="button"
        onClick={() => setDrawerOpen(true)}
        className="w-full rounded-lg border border-emerald-400/30 bg-emerald-500/10 px-3 py-2 text-left text-sm font-medium text-emerald-200 transition hover:bg-emerald-500/20"
        aria-label={ariaLabel}
      >
        {buttonTitle}
        <span className="ml-1 tabular-nums text-emerald-300/80">
          {countLabel}
        </span>
      </button>
    ) : placement === "desktop-nav" ? (
      <button
        type="button"
        onClick={() => setDrawerOpen(true)}
        className="hidden shrink-0 rounded-lg border border-emerald-400/40 bg-emerald-500/15 px-2.5 py-1.5 text-xs font-semibold text-emerald-200 transition hover:bg-emerald-500/25 md:inline-flex"
        aria-label={ariaLabel}
      >
        {buttonTitle}
        <span className="ml-1 tabular-nums text-emerald-300/80">
          {countLabel}
        </span>
      </button>
    ) : (
      <button
        type="button"
        onClick={() => setDrawerOpen(true)}
        className="md:hidden shrink-0 rounded-lg border border-emerald-400/40 bg-emerald-500/15 px-2.5 py-1.5 text-xs font-semibold text-emerald-200 transition hover:bg-emerald-500/25"
        aria-label={ariaLabel}
      >
        {buttonTitle}
        <span className="ml-1 tabular-nums text-emerald-300/80">
          {countLabel}
        </span>
      </button>
    )

  const drawerOverlayClass =
    placement === "desktop-nav"
      ? "fixed inset-0 z-[10000]"
      : "fixed inset-0 z-[10000] md:hidden"

  return (
    <>
      {openButton}

      {drawerOpen ? (
        <div
          className={drawerOverlayClass}
          role="presentation"
          onClick={closeDrawer}
        >
          <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" aria-hidden />
          <div
            role="dialog"
            aria-modal="true"
            aria-label={`${drawerTitle} checklist`}
            className="absolute right-0 top-16 bottom-0 flex w-full max-w-md flex-col border-l border-white/10 bg-[#0b1f3a] shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex shrink-0 items-center justify-between border-b border-white/10 px-4 py-3">
              <h2 className="text-base font-semibold text-white">
                {drawerTitle}
              </h2>
              <ModalCloseButton onClick={closeDrawer} />
            </div>
            <div className="min-h-0 flex-1 overflow-y-auto p-4 pb-6">
              <GettingStartedChecklist
                progress={progress}
                userId={user.id}
                profileId={user.id}
                firstPrivateTradeId={signals.firstPrivateTradeId}
                onChecklistRefresh={() => void refreshChecklistSignals()}
                alwaysExpanded
                embedded
              />
              {foundingChallengeEligible ? (
                <div className="mt-7 border-t border-white/10 pt-6">
                  <TraxsProForLifeCard
                    referralCode={profile?.referral_code}
                    onAwarded={refreshProfile}
                  />
                </div>
              ) : null}
            </div>
          </div>
        </div>
      ) : null}
    </>
  )
}
