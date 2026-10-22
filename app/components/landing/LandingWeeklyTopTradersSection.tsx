"use client"

import Link from "next/link"
import ExploreTopPerformersSection from "@/app/components/explore/ExploreTopPerformersSection"
import type { WeeklyTopPerformersPayload } from "@/lib/weeklyTopPerformersBuild"
import {
  LANDING_HEADLINE_SM,
  LANDING_LEAD,
  LANDING_LEAD_GAP,
  LANDING_SECTION_BORDER,
  LANDING_SECTION_SHELL,
  LANDING_SECTION_SPACING,
} from "@/lib/landingPageUi"

function landingWeeklyTitle(payload: WeeklyTopPerformersPayload): string {
  if (!payload.isHistoricalPeriod && payload.period?.kind === "current_week") {
    return "Weekly Top Traders"
  }
  return payload.periodTitle
}

export default function LandingWeeklyTopTradersSection({
  initialPayload,
}: {
  initialPayload: WeeklyTopPerformersPayload
}) {
  if (!initialPayload.period && initialPayload.performers.length === 0) {
    return null
  }

  const title = landingWeeklyTitle(initialPayload)

  return (
    <section
      id="weekly-top-traders"
      className={`relative z-10 ${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}
      aria-labelledby="weekly-top-traders-heading"
    >
      <div className={LANDING_SECTION_SHELL}>
        <div className="mx-auto max-w-3xl text-center">
          <div className="flex flex-col items-center gap-3 sm:flex-row sm:justify-center sm:gap-4">
            <h2 id="weekly-top-traders-heading" className={LANDING_HEADLINE_SM}>
              {title}
            </h2>
            <Link
              href="/leaderboard"
              className="shrink-0 rounded-lg border border-white/10 bg-white/5 px-3 py-1.5 text-xs font-semibold text-blue-300 transition hover:border-blue-400/30 hover:bg-white/10 hover:text-blue-200 md:text-sm"
            >
              View Leaderboard
            </Link>
          </div>
          <p className={`${LANDING_LEAD} mx-auto ${LANDING_LEAD_GAP}`}>
            {initialPayload.periodSubtitle}
          </p>
        </div>

        <div className="mt-8 md:mt-10">
          <ExploreTopPerformersSection
            performers={initialPayload.performers}
            hasLeaderboardPeriod={initialPayload.period != null}
            showSectionHeader={false}
            loading={false}
            error={null}
            onRetry={() => {}}
          />
        </div>
      </div>
    </section>
  )
}
