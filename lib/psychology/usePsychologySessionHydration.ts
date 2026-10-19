"use client"

import { useEffect, useState } from "react"
import { useUserProfile } from "@/lib/useUserProfile"
import {
  hydratePsychologySessionIfEmpty,
  type PsychologySessionSnapshot,
} from "./hydratePsychologySession.ts"
import {
  computePsychologyInsightsUnlockProgress,
  type PsychologyInsightsUnlockProgress,
} from "./unlockProgress.ts"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import type { PsychologyCoachSummary } from "./reports/coach.ts"
import type { PsychologyAnalyticsReport, PsychologyCoachFacts } from "./reports/types.ts"

export function usePsychologySessionHydration() {
  const { user } = useUserProfile()
  const [ready, setReady] = useState(false)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [report, setReport] = useState<PsychologyAnalyticsReport | null>(null)
  const [facts, setFacts] = useState<PsychologyCoachFacts | null>(null)
  const [summary, setSummary] = useState<PsychologyCoachSummary | null>(null)
  const [unlock, setUnlock] = useState<PsychologyInsightsUnlockProgress | null>(null)

  useEffect(() => {
    if (!user?.id) {
      setReady(true)
      return
    }

    let cancelled = false
    setReady(false)
    setLoadError(null)

    void (async () => {
      try {
        const snapshot: PsychologySessionSnapshot =
          await hydratePsychologySessionIfEmpty(user.id, [])
        if (cancelled) return
        setReport(snapshot.report)
        setFacts(snapshot.facts)
        setSummary(snapshot.summary)
        setUnlock(
          computePsychologyInsightsUnlockProgress(
            snapshot.journalTrades,
            snapshot.checkIns
          )
        )
      } catch (error) {
        if (!cancelled) {
          setLoadError(toUserFacingErrorMessage(error))
        }
      } finally {
        if (!cancelled) setReady(true)
      }
    })()

    return () => {
      cancelled = true
    }
  }, [user?.id])

  return { ready, loadError, report, facts, summary, unlock }
}
