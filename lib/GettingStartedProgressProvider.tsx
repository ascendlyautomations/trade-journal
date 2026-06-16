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
import type { FeedbackPopupInput } from "@/app/components/ui/feedback-popup-types"
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
  followCount: 0,
  hasEverJoinedOtherRoom: false,
  hasPublicTrade: false,
  firstPrivateTradeId: null,
}

function computeProgressFromSignals(
  signals: GettingStartedChecklistSignals,
  userId: string
) {
  const base = computeGettingStartedProgress({
    onboardingCompleted: signals.onboardingCompleted,
    tradeCount: signals.tradeCount,
    profilePostCount: signals.profilePostCount,
    followCount: signals.followCount,
    hasEverJoinedOtherRoom: signals.hasEverJoinedOtherRoom,
    hasPublicTrade: signals.hasPublicTrade,
  })
  return applyStickyGettingStartedProgress(base, userId, {
    profilePostCount: signals.profilePostCount,
  })
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
  const refreshGenerationRef = useRef(0)
  const userIdRef = useRef<string | null>(null)
  const seedDoneForUserIdRef = useRef<string | null>(null)
  const previousCompletedCountRef = useRef(0)
  const pendingRefreshRef = useRef(false)
  const refreshTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const showPopupRef = useRef(showPopup)
  const prevMountedUserIdRef = useRef<string | null>(null)

  userIdRef.current = user?.id ?? null
  showPopupRef.current = showPopup

  const applyProgressPopups = useCallback(
    (
      newProgress: ReturnType<typeof computeGettingStartedProgress>,
      userId: string,
      previousCompletedCount: number
    ) => {
      const popups: FeedbackPopupInput[] = []

      if (seedDoneForUserIdRef.current !== userId) {
        seedDoneForUserIdRef.current = userId
        const completionPopup = seedGettingStartedProgressPopupsIfNeeded(
          newProgress,
          userId
        )
        if (completionPopup) popups.push(completionPopup)
        previousCompletedCountRef.current = newProgress.completedCount
        return popups
      }

      if (newProgress.completedCount > previousCompletedCount) {
        const { stepPopup, completionPopup } =
          resolveGettingStartedProgressTransition(newProgress, userId)
        if (stepPopup) popups.push(stepPopup)
        if (completionPopup) popups.push(completionPopup)
      }

      previousCompletedCountRef.current = newProgress.completedCount
      return popups
    },
    []
  )

  const refreshChecklistSignals = useCallback(async () => {
    const userId = userIdRef.current
    if (!userId) {
      setSignals(EMPTY_SIGNALS)
      setSignalsReady(false)
      return
    }

    const generation = ++refreshGenerationRef.current
    const previousCompletedCount = previousCompletedCountRef.current
    const next = await fetchGettingStartedChecklistSignals(supabase, userId)
    if (generation !== refreshGenerationRef.current) return

    const newProgress = computeProgressFromSignals(next, userId)

    setSignals(next)
    setSignalsReady(true)

    const popups = applyProgressPopups(
      newProgress,
      userId,
      previousCompletedCount
    )
    for (const popup of popups) {
      showPopupRef.current(popup)
    }
  }, [applyProgressPopups])

  const scheduleRefreshChecklistSignals = useCallback(() => {
    if (!userIdRef.current) {
      pendingRefreshRef.current = true
      return
    }
    if (refreshTimeoutRef.current) {
      clearTimeout(refreshTimeoutRef.current)
    }
    refreshTimeoutRef.current = setTimeout(() => {
      refreshTimeoutRef.current = null
      void refreshChecklistSignals()
    }, 250)
  }, [refreshChecklistSignals])

  useEffect(() => {
    const nextUserId = user?.id ?? null

    if (nextUserId !== prevMountedUserIdRef.current) {
      seedDoneForUserIdRef.current = null
      previousCompletedCountRef.current = 0
      pendingRefreshRef.current = false
      prevMountedUserIdRef.current = nextUserId
    }

    if (!nextUserId) {
      setSignals(EMPTY_SIGNALS)
      setSignalsReady(false)
      return
    }

    void refreshChecklistSignals().then(() => {
      if (pendingRefreshRef.current) {
        pendingRefreshRef.current = false
        scheduleRefreshChecklistSignals()
      }
    })
  }, [user?.id, refreshChecklistSignals, scheduleRefreshChecklistSignals])

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
    if (!user?.id) {
      return computeGettingStartedProgress({
        onboardingCompleted: false,
        tradeCount: 0,
        profilePostCount: 0,
        followCount: 0,
        hasEverJoinedOtherRoom: false,
        hasPublicTrade: false,
      })
    }
    return computeProgressFromSignals(signals, user.id)
  }, [user?.id, signals])

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
