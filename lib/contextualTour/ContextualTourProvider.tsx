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
import { usePathname, useRouter } from "next/navigation"
import { CONTEXTUAL_TOUR_DASHBOARD, informationalStepCount } from "./catalog"
import {
  CONTEXTUAL_TOUR_RESOLVE_TIMEOUT_MS,
  domRectToTourRect,
  findTourTargetElement,
  isRenderableSpotlight,
  isStableRect,
  isUsableRect,
  needsScroll,
  skipsTourAutoscroll,
  type TourRect,
} from "./geometry"
import {
  clearContextualTourAwaitingInvite,
  hasContextualTourAwaitingInvite,
} from "./awaitingInvite"
import { dismissTour, dismissedVersion } from "./progressStore"
import {
  countsTowardProgress,
  stepRole,
  type ContextualTourPhase,
  type ContextualTourStep,
  type ContextualTourSurface,
  type ContextualTourTargetId,
} from "./types"
import {
  pathnameMatchesTourSurface,
  routeForTourSurface,
} from "./routes"
import {
  dispatchContextualTourSettingsTab,
  settingsTabForTourTarget,
} from "./settingsTourTab"

type ContextualTourContextValue = {
  phase: ContextualTourPhase
  isActive: boolean
  showsOverlay: boolean
  stepIndex: number
  visibleStepIndex: number
  currentStep: ContextualTourStep | null
  visibleStep: ContextualTourStep | null
  progressLabel: string
  isFinalStep: boolean
  showsExplanationCard: boolean
  spotlightRect: TourRect | null
  measuresTarget: (target: ContextualTourTargetId) => boolean
  showInvite: boolean
  openInvite: () => void
  tryOpenPostOnboardingInvite: (forUserId: string) => void
  acceptInvite: () => void
  declineInvite: () => void
  beginReplay: () => void
  skip: () => void
  next: () => void
  back: () => void
  finish: () => void
}

const ContextualTourContext = createContext<ContextualTourContextValue | null>(
  null
)

export function useContextualTour(): ContextualTourContextValue {
  const ctx = useContext(ContextualTourContext)
  if (!ctx) {
    throw new Error("useContextualTour must be used within ContextualTourProvider")
  }
  return ctx
}

export function useContextualTourOptional(): ContextualTourContextValue | null {
  return useContext(ContextualTourContext)
}

function spotlightTargetForStep(
  step: ContextualTourStep | null
): ContextualTourTargetId | null {
  if (!step) return null
  const role = stepRole(step)
  if (role === "sectionContinue" || role === "finish") return null
  return step.target ?? null
}

type ProviderProps = {
  userId: string | null
  children: ReactNode
}

export function ContextualTourProvider({ userId, children }: ProviderProps) {
  const router = useRouter()
  const pathname = usePathname() ?? ""
  const definition = CONTEXTUAL_TOUR_DASHBOARD

  const [phase, setPhase] = useState<ContextualTourPhase>("idle")
  const [stepIndex, setStepIndex] = useState(0)
  const [displayedStepIndex, setDisplayedStepIndex] = useState(0)
  const [spotlightRect, setSpotlightRect] = useState<TourRect | null>(null)
  const [hasPresentedStep, setHasPresentedStep] = useState(false)
  const [showInvite, setShowInvite] = useState(false)
  const previousFrameRef = useRef<TourRect | null>(null)
  const resolveStartedAtRef = useRef<number | null>(null)
  const scrollIssuedForStepRef = useRef<number | null>(null)
  const rafRef = useRef<number | null>(null)
  const mountedRef = useRef(true)

  const currentStep = definition.steps[stepIndex] ?? null
  const visibleStepIndex = phase === "presenting" ? stepIndex : displayedStepIndex
  const visibleStep = definition.steps[visibleStepIndex] ?? null

  const isActive = phase !== "idle"
  const showsOverlay =
    phase === "presenting" || (phase === "measuring" && hasPresentedStep)

  const progressTotal = informationalStepCount(definition)

  const progressLabel = useMemo(() => {
    let index = 0
    for (let i = 0; i <= visibleStepIndex && i < definition.steps.length; i++) {
      if (countsTowardProgress(stepRole(definition.steps[i]!))) {
        if (i === visibleStepIndex) {
          return `${index + 1} of ${progressTotal}`
        }
        index++
      }
    }
    return ""
  }, [definition.steps, progressTotal, visibleStepIndex])

  const isFinalStep = currentStep ? stepRole(currentStep) === "finish" : false

  const showsExplanationCard =
    phase === "presenting" &&
    (currentStep ? countsTowardProgress(stepRole(currentStep)) : false)

  const endTour = useCallback(
    (dismiss: boolean) => {
      if (dismiss && userId) {
        dismissTour(userId, definition.id, definition.version)
      }
      setPhase("idle")
      setStepIndex(0)
      setDisplayedStepIndex(0)
      setSpotlightRect(null)
      setHasPresentedStep(false)
      previousFrameRef.current = null
      resolveStartedAtRef.current = null
      scrollIssuedForStepRef.current = null
    },
    [definition.id, definition.version, userId]
  )

  const navigateToSurface = useCallback(
    (surface: ContextualTourSurface) => {
      if (!userId) return
      const route = routeForTourSurface(surface, userId)
      if (!pathnameMatchesTourSurface(pathname, surface, userId)) {
        router.push(route)
      }
    },
    [pathname, router, userId]
  )

  const applySettingsTabForStep = useCallback((step: ContextualTourStep) => {
    if (step.surface !== "settings" || !step.target) return
    const tab = settingsTabForTourTarget(step.target)
    if (tab) dispatchContextualTourSettingsTab(tab)
  }, [])

  const startMeasuringStep = useCallback(
    (index: number) => {
      const step = definition.steps[index]
      if (!step || !userId) return

      setStepIndex(index)
      setDisplayedStepIndex(index)
      setPhase("measuring")
      setSpotlightRect(null)
      previousFrameRef.current = null
      resolveStartedAtRef.current = performance.now()
      scrollIssuedForStepRef.current = null

      navigateToSurface(step.surface)
      applySettingsTabForStep(step)
    },
    [applySettingsTabForStep, definition.steps, navigateToSurface, userId]
  )

  const beginReplay = useCallback(() => {
    if (!userId) return
    setShowInvite(false)
    setHasPresentedStep(false)
    startMeasuringStep(0)
  }, [startMeasuringStep, userId])

  const openInvite = useCallback(() => {
    if (phase !== "idle") return
    setShowInvite(true)
  }, [phase])

  const tryOpenPostOnboardingInvite = useCallback(
    (forUserId: string) => {
      if (!userId || forUserId !== userId) return
      if (phase !== "idle" || showInvite) return

      const dismissed = dismissedVersion(forUserId, definition.id)
      if (dismissed >= definition.version) {
        clearContextualTourAwaitingInvite(forUserId)
        return
      }
      if (!hasContextualTourAwaitingInvite(forUserId)) return
      setShowInvite(true)
    },
    [definition.id, definition.version, phase, showInvite, userId]
  )

  const acceptInvite = useCallback(() => {
    if (!userId) return
    clearContextualTourAwaitingInvite(userId)
    setShowInvite(false)
    beginReplay()
  }, [beginReplay, userId])

  const declineInvite = useCallback(() => {
    if (userId) {
      dismissTour(userId, definition.id, definition.version)
      clearContextualTourAwaitingInvite(userId)
    }
    setShowInvite(false)
  }, [definition.id, definition.version, userId])

  const skip = useCallback(() => {
    endTour(true)
  }, [endTour])

  const finish = useCallback(() => {
    endTour(true)
  }, [endTour])

  const advance = useCallback(() => {
    const nextIndex = stepIndex + 1
    if (nextIndex >= definition.steps.length) {
      endTour(true)
      return
    }
    startMeasuringStep(nextIndex)
  }, [definition.steps.length, endTour, startMeasuringStep, stepIndex])

  const next = useCallback(() => {
    const step = definition.steps[stepIndex]
    if (!step) return
    if (stepRole(step) === "finish") {
      finish()
      return
    }
    advance()
  }, [advance, definition.steps, finish, stepIndex])

  const back = useCallback(() => {
    const prevIndex = Math.max(0, stepIndex - 1)
    startMeasuringStep(prevIndex)
  }, [startMeasuringStep, stepIndex])

  const measuresTarget = useCallback(
    (target: ContextualTourTargetId) => {
      if (phase !== "measuring" && phase !== "presenting") return false
      return spotlightTargetForStep(currentStep) === target
    },
    [currentStep, phase]
  )

  useEffect(() => {
    mountedRef.current = true
    return () => {
      mountedRef.current = false
      if (rafRef.current != null) {
        cancelAnimationFrame(rafRef.current)
      }
    }
  }, [])

  useEffect(() => {
    if (phase !== "measuring" && phase !== "presenting") return
    if (!userId || !currentStep) return

    if (!pathnameMatchesTourSurface(pathname, currentStep.surface, userId)) {
      return
    }

    if (currentStep.surface === "settings") {
      applySettingsTabForStep(currentStep)
    }

    const targetId = spotlightTargetForStep(currentStep)
    const role = stepRole(currentStep)

    if (role === "sectionContinue" || role === "finish") {
      setPhase("presenting")
      setHasPresentedStep(true)
      setSpotlightRect(null)
      return
    }

    if (!targetId) {
      setPhase("presenting")
      setHasPresentedStep(true)
      return
    }

    const viewport: TourRect = {
      x: 0,
      y: 0,
      width: window.innerWidth,
      height: window.innerHeight,
    }

    const tick = () => {
      if (!mountedRef.current) return
      const step = definition.steps[stepIndex]
      if (!step) return

      const elapsed =
        performance.now() - (resolveStartedAtRef.current ?? performance.now())
      const el = findTourTargetElement(targetId)
      let frame: TourRect | null = null
      if (el) {
        frame = domRectToTourRect(el.getBoundingClientRect())
      }

      if (
        frame &&
        isUsableRect(frame) &&
        !skipsTourAutoscroll(targetId) &&
        scrollIssuedForStepRef.current !== stepIndex &&
        needsScroll(frame, viewport, 72, 220)
      ) {
        scrollIssuedForStepRef.current = stepIndex
        el?.scrollIntoView({ block: "center", inline: "nearest", behavior: "smooth" })
      }

      const previous = previousFrameRef.current
      if (
        frame &&
        isUsableRect(frame) &&
        previous &&
        isStableRect(previous, frame)
      ) {
        const showSpotlight = isRenderableSpotlight(frame, viewport)
        if (showSpotlight || step.presentsIfUnmeasured) {
          setSpotlightRect(showSpotlight ? frame : null)
          setPhase("presenting")
          setHasPresentedStep(true)
          setDisplayedStepIndex(stepIndex)
          previousFrameRef.current = null
          resolveStartedAtRef.current = null
          return
        }
      }

      if (frame && isUsableRect(frame)) {
        previousFrameRef.current = frame
      }

      if (elapsed >= CONTEXTUAL_TOUR_RESOLVE_TIMEOUT_MS) {
        if (step.presentsIfUnmeasured) {
          setSpotlightRect(null)
          setPhase("presenting")
          setHasPresentedStep(true)
          setDisplayedStepIndex(stepIndex)
        } else {
          advance()
        }
        return
      }

      rafRef.current = requestAnimationFrame(tick)
    }

    rafRef.current = requestAnimationFrame(tick)

    return () => {
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current)
    }
  }, [
    advance,
    applySettingsTabForStep,
    currentStep,
    definition.steps,
    pathname,
    phase,
    stepIndex,
    userId,
  ])

  useEffect(() => {
    if (phase !== "presenting") return
    const targetId = spotlightTargetForStep(currentStep)
    if (!targetId) return

    const onLayout = () => {
      const el = findTourTargetElement(targetId)
      if (!el) return
      const frame = domRectToTourRect(el.getBoundingClientRect())
      const viewport: TourRect = {
        x: 0,
        y: 0,
        width: window.innerWidth,
        height: window.innerHeight,
      }
      if (isRenderableSpotlight(frame, viewport)) {
        setSpotlightRect(frame)
      }
    }

    window.addEventListener("resize", onLayout)
    window.addEventListener("scroll", onLayout, true)
    const interval = window.setInterval(onLayout, 400)
    return () => {
      window.removeEventListener("resize", onLayout)
      window.removeEventListener("scroll", onLayout, true)
      window.clearInterval(interval)
    }
  }, [currentStep, phase])

  const value = useMemo<ContextualTourContextValue>(
    () => ({
      phase,
      isActive,
      showsOverlay,
      stepIndex,
      visibleStepIndex,
      currentStep,
      visibleStep,
      progressLabel,
      isFinalStep,
      showsExplanationCard,
      spotlightRect,
      measuresTarget,
      showInvite,
      openInvite,
      tryOpenPostOnboardingInvite,
      acceptInvite,
      declineInvite,
      beginReplay,
      skip,
      next,
      back,
      finish,
    }),
    [
      acceptInvite,
      back,
      beginReplay,
      currentStep,
      declineInvite,
      finish,
      isActive,
      isFinalStep,
      measuresTarget,
      next,
      openInvite,
      phase,
      progressLabel,
      showInvite,
      tryOpenPostOnboardingInvite,
      showsExplanationCard,
      showsOverlay,
      skip,
      spotlightRect,
      stepIndex,
      visibleStep,
      visibleStepIndex,
    ]
  )

  return (
    <ContextualTourContext.Provider value={value}>
      {children}
    </ContextualTourContext.Provider>
  )
}

/** Presents the post-onboarding invite when the user lands on Dashboard. */
export function useContextualTourPostOnboardingInvite(options: {
  enabled: boolean
  userId: string | null
  onDashboard: boolean
}) {
  const tour = useContextualTourOptional()
  const tryOpen = tour?.tryOpenPostOnboardingInvite

  useEffect(() => {
    if (!options.enabled || !tryOpen || !options.userId || !options.onDashboard) {
      return
    }
    tryOpen(options.userId)
  }, [options.enabled, options.onDashboard, options.userId, tryOpen])
}
