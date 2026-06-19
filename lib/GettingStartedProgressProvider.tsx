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
import {
  computeGettingStartedProgress,
  type GettingStartedProgress,
} from "@/lib/gettingStartedChecklist"
import {
  fetchGettingStartedChecklistSignals,
  type GettingStartedChecklistSignals,
} from "@/lib/gettingStartedChecklistSignals"
import { gsDebug } from "@/lib/gettingStartedDebug"
import {
  resolveBaselineProgressPopups,
  resolveGettingStartedProgressPopups,
} from "@/lib/gettingStartedProgressPopups"
import {
  subscribeGettingStartedSignalsRefresh,
  type GettingStartedRefreshDetail,
} from "@/lib/gettingStartedProgressSync"
import { applyStickyGettingStartedProgress } from "@/lib/gettingStartedSticky"
import {
  GETTING_STARTED_INTRO_POPUP_TITLE,
  markGettingStartedIntroSeen,
} from "@/lib/gettingStartedIntro"
import {
  ONBOARDING_COMPLETE_POPUP_TITLE,
  markOnboardingCompletePopupSeen,
} from "@/lib/gettingStartedOnboardingComplete"
import { feedbackPresets } from "@/lib/feedbackPresets"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { supabase } from "@/lib/supabaseClient"

const EMPTY_SIGNALS: GettingStartedChecklistSignals = {
  onboardingCompleted: false,
  hasSeenGettingStartedIntro: false,
  hasSeenOnboardingCompletePopup: false,
  tradeCount: 0,
  profilePostCount: 0,
  followCount: 0,
  hasEverJoinedOtherRoom: false,
  hasPublicTrade: false,
  firstPrivateTradeId: null,
}

function computeRawProgress(
  signals: GettingStartedChecklistSignals
): GettingStartedProgress {
  return computeGettingStartedProgress({
    onboardingCompleted: signals.onboardingCompleted,
    tradeCount: signals.tradeCount,
    profilePostCount: signals.profilePostCount,
    followCount: signals.followCount,
    hasEverJoinedOtherRoom: signals.hasEverJoinedOtherRoom,
    hasPublicTrade: signals.hasPublicTrade,
  })
}

function computeProgressFromSignals(
  signals: GettingStartedChecklistSignals,
  userId: string
) {
  const base = computeRawProgress(signals)
  return applyStickyGettingStartedProgress(base, userId, {
    profilePostCount: signals.profilePostCount,
  })
}

type RefreshOptions = {
  fromUserAction?: boolean
}

type GettingStartedProgressContextValue = {
  signals: GettingStartedChecklistSignals
  progress: ReturnType<typeof computeGettingStartedProgress>
  signalsReady: boolean
  refreshChecklistSignals: (options?: RefreshOptions) => Promise<void>
}

const GettingStartedProgressContext =
  createContext<GettingStartedProgressContextValue | null>(null)

export function GettingStartedProgressProvider({
  children,
}: {
  children: ReactNode
}) {
  const { user, profile, loading: profileLoading } = useUserProfile()
  const { showPopup, closePopup, feedbackModalProps } = useFeedbackPopup()
  const [signals, setSignals] =
    useState<GettingStartedChecklistSignals>(EMPTY_SIGNALS)
  const [signalsReady, setSignalsReady] = useState(false)
  const signalsRef = useRef<GettingStartedChecklistSignals>(EMPTY_SIGNALS)
  const signalsReadyRef = useRef(false)
  const baselineResolvedRef = useRef(false)
  const refreshGenerationRef = useRef(0)
  const userIdRef = useRef<string | null>(null)
  const pendingRefreshRef = useRef(false)
  const popupQueueRef = useRef<FeedbackPopupInput[]>([])
  const popupOpenRef = useRef(false)
  const activePopupTitleRef = useRef<string | undefined>(undefined)
  const introPopupActiveRef = useRef(false)
  const completionPopupActiveRef = useRef(false)
  const showPopupRef = useRef(showPopup)
  const closePopupRef = useRef(closePopup)
  const prevMountedUserIdRef = useRef<string | null>(null)
  const mountCountRef = useRef(0)

  userIdRef.current = user?.id ?? null
  showPopupRef.current = showPopup
  closePopupRef.current = closePopup
  signalsRef.current = signals
  signalsReadyRef.current = signalsReady

  useEffect(() => {
    mountCountRef.current += 1
    gsDebug("provider mount", {
      mountCount: mountCountRef.current,
      userId: user?.id ?? null,
    })
    return () => {
      gsDebug("provider unmount", { mountCount: mountCountRef.current })
    }
  }, [user?.id])

  const drainPopupQueue = useCallback(() => {
    if (popupOpenRef.current) {
      gsDebug("drain blocked: popup already open", {
        queueLength: popupQueueRef.current.length,
      })
      return
    }
    if (popupQueueRef.current.length === 0) {
      gsDebug("drain skipped: empty queue")
      return
    }
    const next = popupQueueRef.current.shift()
    if (!next) return
    popupOpenRef.current = true
    activePopupTitleRef.current = next.title
    gsDebug("dispatching popup", {
      title: next.title,
      queueRemaining: popupQueueRef.current.length,
    })
    showPopupRef.current(next)
  }, [])

  const enqueuePopups = useCallback(
    (popups: FeedbackPopupInput[]) => {
      if (popups.length === 0) {
        gsDebug("enqueue skipped: no popups")
        return
      }
      gsDebug("enqueue popups", {
        count: popups.length,
        titles: popups.map((p) => p.title),
        queueBefore: popupQueueRef.current.length,
      })
      popupQueueRef.current.push(...popups)
      gsDebug("queue length:", popupQueueRef.current.length)
      drainPopupQueue()
    },
    [drainPopupQueue]
  )

  const handlePopupClose = useCallback(() => {
    const closedTitle = activePopupTitleRef.current
    const isIntroPopup =
      introPopupActiveRef.current ||
      closedTitle === GETTING_STARTED_INTRO_POPUP_TITLE
    const isCompletionPopup =
      completionPopupActiveRef.current ||
      closedTitle === ONBOARDING_COMPLETE_POPUP_TITLE
    const userId = userIdRef.current

    gsDebug("modal close", {
      closedTitle,
      isIntroPopup,
      isCompletionPopup,
      userId: userId?.slice(0, 8),
    })

    closePopupRef.current()
    popupOpenRef.current = false
    activePopupTitleRef.current = undefined

    if (isIntroPopup && userId) {
      introPopupActiveRef.current = false
      void (async () => {
        const ok = await markGettingStartedIntroSeen(supabase, userId)
        gsDebug("intro dismiss persisted", { ok })
        if (ok) {
          setSignals((prev) => ({ ...prev, hasSeenGettingStartedIntro: true }))
          signalsRef.current = {
            ...signalsRef.current,
            hasSeenGettingStartedIntro: true,
          }
        }
      })()
    }

    if (isCompletionPopup && userId) {
      completionPopupActiveRef.current = false
      void (async () => {
        const ok = await markOnboardingCompletePopupSeen(supabase, userId)
        gsDebug("completion popup dismiss persisted", { ok })
        if (ok) {
          setSignals((prev) => ({
            ...prev,
            hasSeenOnboardingCompletePopup: true,
          }))
          signalsRef.current = {
            ...signalsRef.current,
            hasSeenOnboardingCompletePopup: true,
          }
        }
      })()
    }

    requestAnimationFrame(() => {
      drainPopupQueue()
    })
  }, [drainPopupQueue])

  const refreshChecklistSignals = useCallback(
    async (options?: RefreshOptions) => {
      const userId = userIdRef.current
      const fromUserAction = options?.fromUserAction === true

      if (!userId) {
        gsDebug("refresh skipped: no userId")
        setSignals(EMPTY_SIGNALS)
        signalsRef.current = EMPTY_SIGNALS
        setSignalsReady(false)
        signalsReadyRef.current = false
        return
      }

      const generation = ++refreshGenerationRef.current
      const isBaselineFetch = !baselineResolvedRef.current
      const preFetchSnapshot = computeRawProgress(signalsRef.current)

      gsDebug("refresh start", {
        generation,
        fromUserAction,
        isBaselineFetch,
        preFetchCompletedCount: preFetchSnapshot.completedCount,
        signalsReady: signalsReadyRef.current,
      })

      const preloadedProfileSignals =
        profile != null
          ? {
              onboardingCompleted: profile.onboarding_completed === true,
              hasSeenGettingStartedIntro:
                profile.has_seen_getting_started_intro === true,
              hasSeenOnboardingCompletePopup:
                profile.has_seen_onboarding_complete_popup === true,
            }
          : undefined

      const next = await fetchGettingStartedChecklistSignals(
        supabase,
        userId,
        preloadedProfileSignals
      )
      if (generation !== refreshGenerationRef.current) {
        gsDebug("refresh discarded: stale generation", {
          generation,
          current: refreshGenerationRef.current,
        })
        return
      }

      const newRawProgress = computeRawProgress(next)

      gsDebug("refresh fetched", {
        generation,
        tradeCount: next.tradeCount,
        completedCount: newRawProgress.completedCount,
        hasSeenGettingStartedIntro: next.hasSeenGettingStartedIntro,
        hasSeenOnboardingCompletePopup: next.hasSeenOnboardingCompletePopup,
        onboardingCompleted: next.onboardingCompleted,
        completeIds: newRawProgress.items
          .filter((i) => i.complete)
          .map((i) => i.id),
      })

      setSignals(next)
      signalsRef.current = next
      setSignalsReady(true)
      signalsReadyRef.current = true

      const batch = isBaselineFetch
        ? fromUserAction
          ? resolveGettingStartedProgressPopups(
              preFetchSnapshot,
              newRawProgress,
              userId,
              next.hasSeenOnboardingCompletePopup
            )
          : resolveBaselineProgressPopups(
              newRawProgress,
              userId,
              next.hasSeenOnboardingCompletePopup
            )
        : resolveGettingStartedProgressPopups(
            preFetchSnapshot,
            newRawProgress,
            userId,
            next.hasSeenOnboardingCompletePopup
          )

      if (isBaselineFetch) {
        baselineResolvedRef.current = true
        gsDebug("baseline resolved", { fromUserAction })
      }

      const popups: FeedbackPopupInput[] = [...batch.stepPopups]
      if (batch.completionPopup) {
        completionPopupActiveRef.current = true
        popups.push(batch.completionPopup)
      }

      if (
        isBaselineFetch &&
        next.onboardingCompleted &&
        !next.hasSeenGettingStartedIntro
      ) {
        introPopupActiveRef.current = true
        popups.unshift(feedbackPresets.gettingStartedIntro())
        gsDebug("intro popup queued", {
          hasSeenGettingStartedIntro: next.hasSeenGettingStartedIntro,
          onboardingCompleted: next.onboardingCompleted,
        })
      }

      gsDebug("popup batch", {
        stepCount: batch.stepPopups.length,
        hasCompletion: Boolean(batch.completionPopup),
        hasSeenOnboardingCompletePopup: next.hasSeenOnboardingCompletePopup,
        hasIntro:
          isBaselineFetch &&
          next.onboardingCompleted &&
          !next.hasSeenGettingStartedIntro,
      })

      enqueuePopups(popups)
    },
    [enqueuePopups, profile]
  )

  useEffect(() => {
    const nextUserId = user?.id ?? null

    if (nextUserId !== prevMountedUserIdRef.current) {
      pendingRefreshRef.current = false
      popupQueueRef.current = []
      popupOpenRef.current = false
      introPopupActiveRef.current = false
      completionPopupActiveRef.current = false
      baselineResolvedRef.current = false
      prevMountedUserIdRef.current = nextUserId
      gsDebug("user changed, reset baseline", { userId: nextUserId })
    }

    if (!nextUserId) {
      setSignals(EMPTY_SIGNALS)
      signalsRef.current = EMPTY_SIGNALS
      setSignalsReady(false)
      signalsReadyRef.current = false
      baselineResolvedRef.current = false
      return
    }

    if (profileLoading) return

    void refreshChecklistSignals().then(() => {
      if (pendingRefreshRef.current) {
        pendingRefreshRef.current = false
        void refreshChecklistSignals({ fromUserAction: true })
      }
    })
  }, [user?.id, profileLoading, refreshChecklistSignals])

  useEffect(() => {
    return subscribeGettingStartedSignalsRefresh(
      (detail?: GettingStartedRefreshDetail) => {
        const fromUserAction = detail?.fromUserAction === true
        gsDebug("signals refresh event", { fromUserAction })
        if (!userIdRef.current) {
          pendingRefreshRef.current = true
          return
        }
        void refreshChecklistSignals({ fromUserAction })
      }
    )
  }, [refreshChecklistSignals])

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

  useEffect(() => {
    gsDebug("modal open state", {
      isOpen: feedbackModalProps.isOpen,
      title: feedbackModalProps.title,
    })
  }, [
    feedbackModalProps.isOpen,
    feedbackModalProps.title,
    feedbackModalProps.message,
  ])

  return (
    <GettingStartedProgressContext.Provider value={value}>
      {children}
      {user?.id ? (
        <FeedbackModal
          {...feedbackModalProps}
          onClose={handlePopupClose}
          overlayClassName="z-[1200]"
        />
      ) : null}
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

