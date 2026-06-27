"use client"

import { useCallback, useEffect, useState } from "react"
import { usePathname } from "next/navigation"
import GettingStartedChecklist from "@/app/components/dashboard/GettingStartedChecklist"
import { useGettingStartedProgress } from "@/lib/GettingStartedProgressProvider"
import { shouldOfferGettingStartedChecklist } from "@/lib/gettingStartedChecklist"
import { useUserProfile } from "@/lib/useUserProfile"

export default function GettingStartedMobileEntry() {
  const pathname = usePathname()
  const { user } = useUserProfile()
  const {
    progress,
    signals,
    signalsReady,
    refreshChecklistSignals,
  } = useGettingStartedProgress()
  const [drawerOpen, setDrawerOpen] = useState(false)

  const visible =
    signalsReady &&
    shouldOfferGettingStartedChecklist(user?.id, {
      hasSeenOnboardingCompletePopup: signals.hasSeenOnboardingCompletePopup,
      allComplete: progress.allComplete,
    })

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

  useEffect(() => {
    if (!drawerOpen) return
    const html = document.documentElement
    const body = document.body
    const prevHtmlOverflow = html.style.overflow
    const prevBodyOverflow = body.style.overflow
    html.style.overflow = "hidden"
    body.style.overflow = "hidden"
    return () => {
      html.style.overflow = prevHtmlOverflow
      body.style.overflow = prevBodyOverflow
    }
  }, [drawerOpen])

  if (!visible || !user?.id) return null

  const { completedCount, totalCount } = progress

  return (
    <>
      <button
        type="button"
        onClick={() => setDrawerOpen(true)}
        className="md:hidden shrink-0 rounded-lg border border-emerald-400/40 bg-emerald-500/15 px-2.5 py-1.5 text-xs font-semibold text-emerald-200 transition hover:bg-emerald-500/25"
        aria-label={`Complete setup, ${completedCount} of ${totalCount} tasks done`}
      >
        Complete Setup
        <span className="ml-1 tabular-nums text-emerald-300/80">
          ({completedCount}/{totalCount})
        </span>
      </button>

      {drawerOpen ? (
        <div
          className="fixed inset-0 z-[10000] md:hidden"
          role="presentation"
          onClick={closeDrawer}
        >
          <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" aria-hidden />
          <div
            role="dialog"
            aria-modal="true"
            aria-label="Complete setup checklist"
            className="absolute right-0 top-16 bottom-0 flex w-full max-w-md flex-col border-l border-white/10 bg-[#0b1f3a] shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex shrink-0 items-center justify-between border-b border-white/10 px-4 py-3">
              <h2 className="text-base font-semibold text-white">Complete Setup</h2>
              <button
                type="button"
                onClick={closeDrawer}
                className="rounded-lg px-2 py-1 text-lg leading-none text-gray-400 transition hover:bg-white/10 hover:text-white"
                aria-label="Close setup checklist"
              >
                ×
              </button>
            </div>
            <div className="min-h-0 flex-1 overflow-y-auto p-4">
              <GettingStartedChecklist
                progress={progress}
                userId={user.id}
                profileId={user.id}
                firstPrivateTradeId={signals.firstPrivateTradeId}
                onChecklistRefresh={() => void refreshChecklistSignals()}
                alwaysExpanded
                embedded
              />
            </div>
          </div>
        </div>
      ) : null}
    </>
  )
}
