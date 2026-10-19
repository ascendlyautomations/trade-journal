"use client"

import {
  displayCheckInDayCountForGate,
  displayTradeCountForGate,
  PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT,
  type PsychologyInsightsUnlockProgress,
} from "@/lib/psychology/unlockProgress"

type PsychologyInsightsRequirementNoticeProps = {
  unlock: PsychologyInsightsUnlockProgress
}

export default function PsychologyInsightsRequirementNotice({
  unlock,
}: PsychologyInsightsRequirementNoticeProps) {
  return (
    <div
      className="rounded-xl border border-white/10 bg-white/10 p-4"
      data-testid="psychologyAnalytics.requirements"
    >
      <h2 className="text-sm font-semibold text-white">
        5 Daily Check-Ins &amp; 5 Trades Required
      </h2>
      <p className="mt-1 text-xs text-gray-400">
        Log check-ins and trade psychology on trading days to unlock personalized
        insight cards on your dashboard. Detailed sections below update as you log
        more data.
      </p>
      <p className="mt-2 text-xs tabular-nums text-gray-300">
        Check-in days {displayCheckInDayCountForGate(unlock)}/
        {PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT}
        {" · "}
        Trades {displayTradeCountForGate(unlock)}/{PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT}
      </p>
    </div>
  )
}
