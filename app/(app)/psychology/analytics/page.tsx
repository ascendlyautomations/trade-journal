"use client"

import Link from "next/link"
import { useSearchParams } from "next/navigation"
import PsychologyAnalyticsDetail from "@/app/components/psychology/PsychologyAnalyticsDetail"
import PsychologyInsightsRequirementNotice from "@/app/components/psychology/PsychologyInsightsRequirementNotice"
import PsychologyProGate from "@/app/components/psychology/PsychologyProGate"
import {
  focusPsychologySection,
  getPsychologySession,
} from "@/lib/psychology/psychologySessionStore"
import { usePsychologySessionHydration } from "@/lib/psychology/usePsychologySessionHydration"
import { showsPsychologyInsightsRequirement } from "@/lib/psychology/unlockProgress"
import { useScrollPageTopOnMount } from "@/lib/useScrollPageTopOnMount"
import { useEffect } from "react"

function PsychologyAnalyticsPageContent() {
  useScrollPageTopOnMount()
  const searchParams = useSearchParams()
  const highlight = searchParams.get("section")?.trim() || null
  const { ready, loadError, report, summary, unlock } = usePsychologySessionHydration()

  useEffect(() => {
    if (highlight) {
      focusPsychologySection(highlight)
    }
  }, [highlight])

  if (!ready) {
    return <p className="text-sm text-gray-400">Loading psychology analytics…</p>
  }

  if (loadError) {
    return (
      <p className="text-sm text-red-400">
        {loadError}{" "}
        <Link href="/dashboard" className="underline">
          Back to Dashboard
        </Link>
      </p>
    )
  }

  if (!report) {
    return (
      <div className="rounded-xl border border-white/10 bg-white/5 p-8 text-center">
        <p className="font-medium text-white">No analytics yet</p>
        <p className="mt-2 text-sm text-gray-500">
          Log trades and daily check-ins to build your psychology analytics.
        </p>
        <Link
          href="/dashboard"
          className="mt-4 inline-block text-sm font-medium text-blue-400"
        >
          Go to Dashboard
        </Link>
      </div>
    )
  }

  const sectionFocus =
    highlight ?? getPsychologySession().highlightedSectionID ?? null
  const showsRequirement = unlock ? showsPsychologyInsightsRequirement(unlock) : false

  return (
    <div className="space-y-6">
      {showsRequirement && unlock ? (
        <PsychologyInsightsRequirementNotice unlock={unlock} />
      ) : null}
      <PsychologyAnalyticsDetail
        report={report}
        summary={summary}
        highlightedSectionID={sectionFocus}
      />
    </div>
  )
}

export default function PsychologyAnalyticsPage() {
  return (
    <main className="tt-psych-experience mx-auto max-w-2xl px-4 py-8 md:py-10">
      <div className="mb-6 flex items-center gap-3">
        <Link href="/dashboard" className="text-sm text-blue-400 hover:text-blue-300">
          ← Dashboard
        </Link>
      </div>
      <h1 className="mb-6 text-2xl font-semibold text-blue-200">Psychology Analytics</h1>
      <PsychologyProGate>
        <PsychologyAnalyticsPageContent />
      </PsychologyProGate>
    </main>
  )
}
