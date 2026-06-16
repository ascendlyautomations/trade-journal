"use client"

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { computeGettingStartedProgress } from "@/lib/gettingStartedChecklist"
import {
  fetchGettingStartedChecklistSignals,
  type GettingStartedChecklistSignals,
} from "@/lib/gettingStartedChecklistSignals"
import {
  resolveGettingStartedProgressTransition,
  seedGettingStartedProgressPopupsIfNeeded,
} from "@/lib/gettingStartedProgressPopups"
import { subscribeGettingStartedSignalsRefresh } from "@/lib/gettingStartedProgressSync"
import { applyStickyGettingStartedProgress } from "@/lib/gettingStartedSticky"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { supabase } from "@/lib/supabaseClient"

const EMPTY_SIGNALS: GettingStartedChecklistSignals = {
  onboardingCompleted: false,
  tradeCount: 0,
  profilePostCount: 0,
  feedPostCount: 0,
  followCount: 0,
  hasEverJoinedOtherRoom: false,
  hasPublicTrade: false,
  firstPrivateTradeId: null,
}

type GettingStartedProgressContextValue = {
  signals: GettingStartedChecklistSignals
  progress: ReturnType<typeof computeGettingStartedProgress>
  signalsReady: boolean
  refreshChecklistSignals: () => Promise<void>
}

const GettingStartedProgressContext =
  createContext<GettingStartedProgressContextValue | null>(null)

export function GettingStartedProgressProvider({
  children,
}: {
  children: ReactNode
}) {
  const { user } = useUserProfile()
  const { showPopup, ...feedbackModalProps } = useFeedbackPopup()
  const [signals, setSignals] =
    useState<GettingStartedChecklistSignals>(EMPTY_SIGNALS)
  const [signalsReady, setSignalsReady] = useState(false)
  const progressPopupsInitializedRef = useRef(false)
  const refreshTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const refreshGenerationRef = useRef(0)

  const refreshChecklistSignals = useCallback(async () => {
    if (!user?.id) {
      setSignals(EMPTY_SIGNALS)
      setSignalsReady(false)
      return
    }

    const generation = ++refreshGenerationRef.current
    const next = await fetchGettingStartedChecklistSignals(supabase, user.id)
    if (generation !== refreshGenerationRef.current) return

    setSignals(next)
    setSignalsReady(true)
  }, [user?.id])

  const scheduleRefreshChecklistSignals = useCallback(() => {
    if (refreshTimeoutRef.current) {
      clearTimeout(refreshTimeoutRef.current)
    }
    refreshTimeoutRef.current = setTimeout(() => {
      refreshTimeoutRef.current = null
      void refreshChecklistSignals()
    }, 150)
  }, [refreshChecklistSignals])

  useEffect(() => {
    progressPopupsInitializedRef.current = false
    if (!user?.id) {
      setSignals(EMPTY_SIGNALS)
      setSignalsReady(false)
      return
    }
    void refreshChecklistSignals()
  }, [user?.id, refreshChecklistSignals])

  useEffect(() => {
    return subscribeGettingStartedSignalsRefresh(scheduleRefreshChecklistSignals)
  }, [scheduleRefreshChecklistSignals])

  useEffect(() => {
    return () => {
      if (refreshTimeoutRef.current) {
        clearTimeout(refreshTimeoutRef.current)
      }
    }
  }, [])

  const progress = useMemo(() => {
    const base = computeGettingStartedProgress({
      onboardingCompleted: signals.onboardingCompleted,
      tradeCount: signals.tradeCount,
      profilePostCount: signals.profilePostCount,
      feedPostCount: signals.feedPostCount,
      followCount: signals.followCount,
      hasEverJoinedOtherRoom: signals.hasEverJoinedOtherRoom,
      hasPublicTrade: signals.hasPublicTrade,
    })
    if (!user?.id) return base
    return applyStickyGettingStartedProgress(base, user.id)
  }, [user?.id, signals])

  useEffect(() => {
    if (!user?.id || !signalsReady) return
    if (progressPopupsInitializedRef.current) return
    progressPopupsInitializedRef.current = true

    const completionPopup = seedGettingStartedProgressPopupsIfNeeded(
      progress,
      user.id
    )
    if (completionPopup) showPopup(completionPopup)
  }, [user?.id, signalsReady, progress, showPopup])

  useEffect(() => {
    if (!user?.id || !signalsReady || !progressPopupsInitializedRef.current) {
      return
    }

    const { stepPopup, completionPopup } =
      resolveGettingStartedProgressTransition(progress, user.id)
    if (stepPopup) showPopup(stepPopup)
    if (completionPopup) showPopup(completionPopup)
  }, [
    user?.id,
    signalsReady,
    progress.completedCount,
    progress.allComplete,
    showPopup,
  ])

  const value = useMemo(
    () => ({
      signals,
      progress,
      signalsReady,
      refreshChecklistSignals,
    }),
    [signals, progress, signalsReady, refreshChecklistSignals]
  )

  return (
    <GettingStartedProgressContext.Provider value={value}>
      {children}
      {user?.id ? <FeedbackModal {...feedbackModalProps} /> : null}
    </GettingStartedProgressContext.Provider>
  )
}

export function useGettingStartedProgress() {
  const context = useContext(GettingStartedProgressContext)
  if (!context) {
    throw new Error(
      "useGettingStartedProgress must be used within GettingStartedProgressProvider"
    )
  }
  return context
}
