"use client"

import Link from "next/link"
import CheckInHistoryHome from "@/app/components/psychology/CheckInHistoryHome"
import {
  PSYCHOLOGY_JOURNAL_EMPTY_DASHBOARD_TRADES,
  usePsychologyJournalInputs,
} from "@/lib/psychology/usePsychologyJournalInputs"
import { useUserProfile } from "@/lib/useUserProfile"
import { useScrollPageTopOnMount } from "@/lib/useScrollPageTopOnMount"
import { MOBILE_WEB_NEUTRAL_PAGE_BG } from "@/lib/mobileWebPageSurface"

export default function CheckInHistoryPage() {
  useScrollPageTopOnMount()
  const { user } = useUserProfile()
  const { checkIns, trades, ready, loadError, refresh } = usePsychologyJournalInputs(
    user?.id,
    PSYCHOLOGY_JOURNAL_EMPTY_DASHBOARD_TRADES
  )

  return (
    <main className={`tt-psych-experience mx-auto max-w-2xl px-4 py-8 md:py-10 max-md:px-3 max-md:py-3 ${MOBILE_WEB_NEUTRAL_PAGE_BG}`}>
      <div className="mb-6 max-md:hidden">
        <Link href="/dashboard" className="text-sm text-blue-400 hover:text-blue-300">
          ← Dashboard
        </Link>
      </div>
      <h1 className="mb-6 text-2xl font-semibold text-blue-200 max-md:hidden">Check-In History</h1>
      {!ready ? (
        <p className="text-sm text-gray-400">Loading history…</p>
      ) : (
        <CheckInHistoryHome
          checkIns={checkIns}
          trades={trades}
          loadError={loadError}
          onRetry={() => void refresh()}
        />
      )}
    </main>
  )
}
