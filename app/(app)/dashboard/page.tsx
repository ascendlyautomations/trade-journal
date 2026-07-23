"use client"

import DashboardFilters from "../../components/dashboard/DashboardFilters"
import NativeIosPullToRefresh from "@/app/components/NativeIosPullToRefresh"
import DashboardHeader from "../../components/dashboard/DashboardHeader"
import GettingStartedChecklist from "../../components/dashboard/GettingStartedChecklist"
import TraxsProForLifeCard from "../../components/dashboard/TraxsProForLifeCard"
import DashboardAnalytics from "../../components/dashboard/DashboardAnalytics"
import DashboardCharts from "../../components/dashboard/DashboardCharts"
import DashboardInsights from "../../components/dashboard/DashboardInsights"
import DashboardModals from "../../components/dashboard/DashboardModals"
import DashboardRecentTrades from "../../components/dashboard/DashboardRecentTrades"
import DashboardTradingReports from "../../components/dashboard/DashboardTradingReports"
import type {
  DashboardAccountRow,
  DashboardTradeRow,
} from "../../components/dashboard/dashboardTypes"
import type { TradingReportsSectionHandle } from "@/app/components/trading-reports/TradingReportsSection"
import dynamic from "next/dynamic"
import {
  useCallback,
  useDeferredValue,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react"
import type {
  DashboardGearPersistedPrefs,
  GearDraftState,
} from "../../components/dashboard/dashboardGearTypes"
import {
  finalizeDrawdownLimitInput,
  sanitizeDashboardAccountFilter,
  sanitizeHydratedDashboardFilters,
  sanitizeDrawdownLimitInput,
  shouldShowPropFirmDashboardLink,
} from "../../components/dashboard/dashboardGearUtils"
import {
  buildAccountFilterOptionsFromRows,
} from "@/lib/tradeAccountDisplay"
import EmptyState from "../../components/ui/EmptyState"
import { SkeletonDashboardShell } from "../../components/ui/skeletons"
import Link from "next/link"
import {
  mirrorAccountSettingsMaxDrawdownLimit,
} from "@/lib/profileSplitMirrorWrites"
import { supabase } from "../../../lib/supabaseClient"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import { isProActive } from "../../../lib/subscription"
import { CREATOR_ACCESS_SUCCESS_MESSAGE } from "@/lib/creatorAccess"
import { filterTradesForPerformanceSharePool } from "@/lib/performanceShare"
import { excludeBacktestTrades } from "@/lib/tradeModeFilters"
import { useCopyTradingGroups } from "@/lib/useCopyTradingGroups"
import {
  isValidAccountFilterValue,
  resolveCopyGroupAccountIdsForFilter,
} from "@/lib/tradeAccountSelection"
import {
  getDashboardTradingDayKey,
} from "@/lib/dashboardTradeDate"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import {
  dispatchGettingStartedSignalsRefresh,
  notifyGettingStartedChecklistMaybeCompleted,
} from "@/lib/gettingStartedProgressSync"
import {
  markStripeReconciliationPending,
  subscribeStripeReconciliationComplete,
} from "@/lib/stripeReconciliation"
import {
  shouldAutoShowGettingStartedChecklist,
} from "@/lib/gettingStartedChecklist"
import {
  auditLogDashboardDecision,
  auditLogDashboardMounted,
} from "@/lib/onboardingChecklistAudit"
import { useGettingStartedProgress } from "@/lib/GettingStartedProgressProvider"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { shouldShowProForLifeCard } from "@/lib/earlyAccess"
import { profilePath } from "@/lib/profileRoutes"
import { usePrefetchSecondaryRoutesWhenReady } from "@/lib/usePrefetchSecondaryRoutesWhenReady"
import { useCachedAccounts, useCachedTrades } from "@/lib/useAppDataCache"
import {
  ensureAccountsLoaded,
  ensureTradesLoaded,
  getCachedTrades,
} from "@/lib/appDataCache"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { useDashboardModals } from "./useDashboardModals"
import { useDashboardAnalytics } from "./useDashboardAnalytics"

const DashboardPremiumPreviewSection = dynamic(
  () => import("../../components/dashboard/DashboardPremiumPreviewSection"),
  { loading: () => <div className="h-48 animate-pulse rounded-xl bg-white/5" /> }
)
function DashboardDeferredSectionsSkeleton() {
  return (
    <div className="space-y-3" aria-hidden>
      <div className="h-72 animate-pulse rounded-xl border border-white/10 bg-white/5" />
      <div className="grid gap-3 md:grid-cols-2">
        <div className="h-48 animate-pulse rounded-xl border border-white/10 bg-white/5" />
        <div className="h-48 animate-pulse rounded-xl border border-white/10 bg-white/5" />
      </div>
    </div>
  )
}

const DASHBOARD_GEAR_PREFS_KEY = "tradetrax_dashboard_prefs_v1"

function loadDashboardGearPrefs(): Partial<DashboardGearPersistedPrefs> | null {
  if (typeof window === "undefined") return null
  try {
    const s = window.localStorage.getItem(DASHBOARD_GEAR_PREFS_KEY)
    if (!s) return null
    const p = JSON.parse(s) as Partial<DashboardGearPersistedPrefs>
    return p && typeof p === "object" ? p : null
  } catch {
    return null
  }
}

function saveDashboardGearPrefs(p: DashboardGearPersistedPrefs) {
  try {
    window.localStorage.setItem(DASHBOARD_GEAR_PREFS_KEY, JSON.stringify(p))
  } catch {
    /* ignore quota / private mode */
  }
}

export default function Dashboard() {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const {
    progress: gettingStartedProgress,
    signals: checklistSignals,
    signalsReady: checklistSignalsReady,
    refreshChecklistSignals,
  } = useGettingStartedProgress()
  const {
    user,
    profile,
    loading: profileLoading,
    setProfile,
    refreshProfile,
  } = useUserProfile()
  const { trades, loading: tradesLoading } = useCachedTrades(user?.id)
  const { accounts: accountRows, loading: accountsLoading } =
    useCachedAccounts(user?.id)
  const isPro = isProActive(profile)
  const { copyGroups } = useCopyTradingGroups(user?.id, isPro)
  const [accountFilter, setAccountFilter] = useState("all")
  const [accountTypeFilter, setAccountTypeFilter] = useState("all")
  const [timeFilter, setTimeFilter] = useState("all")
  const [customRangeStart, setCustomRangeStart] = useState("")
  const [customRangeEnd, setCustomRangeEnd] = useState("")
  const [selectedDate, setSelectedDate] = useState("")
  const [showPublicOnly, setShowPublicOnly] = useState(false)
  const [showControls, setShowControls] = useState(false)
  const [showEquity, setShowEquity] = useState(true)
  const [showDrawdown, setShowDrawdown] = useState(true)
  const [showInsights, setShowInsights] = useState(true)
  const [showSessions, setShowSessions] = useState(true)
  const [showBestSetup, setShowBestSetup] = useState(true)
  const [showWorstSetup, setShowWorstSetup] = useState(true)
  const [showWarnings, setShowWarnings] = useState(true)
  /** Snapshot of gear-panel fields while open; committed on Save. */
  const [gearDraft, setGearDraft] = useState<GearDraftState | null>(null)
  const [ddInputFocused, setDdInputFocused] = useState(false)
  const [savingGearSettings, setSavingGearSettings] = useState(false)
  const {
    performanceShareOpen: showPerformanceShare,
    openPerformanceShare,
    closePerformanceShare,
    quickTradeOpen: showQuickTrade,
    openQuickTrade,
    closeQuickTrade,
    upgradeOpen: showProUpgradeModal,
    openUpgrade: openExportUpgradeModal,
    closeUpgrade,
    importOpen: showImportModal,
    openImport,
    closeImport,
    editingTrade,
    setEditingTrade,
    selectedImage,
    closeImage,
    sendTradeId,
    closeSend,
    closeTrade,
  } = useDashboardModals()
  const tradingReportsRef = useRef<TradingReportsSectionHandle>(null)
  const [deferredSectionsReady, setDeferredSectionsReady] = useState(false)
  const didHydrateDashboardPrefs = useRef(false)
  /** Same fetch as /trades — used only for filter dropdown labels (#account_number vs UUID). */

  const pageDataLoading =
    (profileLoading && !profile) ||
    (tradesLoading && trades.length === 0) ||
    (accountsLoading && accountRows.length === 0)

  const accountById = useMemo(() => {
    const m: Record<string, DashboardAccountRow> = {}
    accountRows.forEach((acc) => {
      m[String(acc.id)] = acc
    })
    return m
  }, [accountRows])

  const accounts = useMemo(
    () => buildAccountFilterOptionsFromRows(accountRows),
    [accountRows]
  )

  const copyGroupAccountIds = useMemo(
    () => resolveCopyGroupAccountIdsForFilter(accountFilter, copyGroups),
    [accountFilter, copyGroups]
  )

  const showPropFirmLink = useMemo(
    () =>
      shouldShowPropFirmDashboardLink({
        accountFilter,
        accountTypeFilter,
        accountById,
      }),
    [accountFilter, accountTypeFilter, accountById]
  )

  const tradesExcludingBacktest = useMemo(
    () => excludeBacktestTrades([...trades]),
    [trades]
  )
  const deferredTradesExcludingBacktest = useDeferredValue(tradesExcludingBacktest)

  function handleDashboardTimeframeChange(value: string) {
    setTimeFilter(value)
    if (value !== "custom") {
      setCustomRangeStart("")
      setCustomRangeEnd("")
    }
  }

  function handleDashboardCustomRangeApply(start: string, end: string) {
    setSelectedDate("")
    setCustomRangeStart(start)
    setCustomRangeEnd(end)
    setTimeFilter("custom")
  }

  const tradesForPerformanceSharePool = useMemo(
    () => {
      if (!showPerformanceShare) return []
      return filterTradesForPerformanceSharePool(tradesExcludingBacktest, {
        selectedDate,
        accountFilter,
        accountTypeFilter,
        showPublicOnly,
        accountById,
        copyGroupAccountIds,
      })
    },
    [
      showPerformanceShare,
      tradesExcludingBacktest,
      selectedDate,
      accountFilter,
      accountTypeFilter,
      showPublicOnly,
      accountById,
      copyGroupAccountIds,
    ]
  )

  // Refresh trades + accounts when data changes (import, checkout) — otherwise reuse cache.
  const refreshDashboardData = useCallback(async () => {
    const currentUserId = user?.id
    if (!currentUserId) return

    await Promise.all([
      ensureTradesLoaded(supabase, currentUserId, { force: true }),
      ensureAccountsLoaded(supabase, currentUserId, { force: true }),
    ])
  }, [user?.id])

  const handleImportModalComplete = useCallback(async () => {
    closeImport()
    void import("@/lib/nativeHaptics").then(({ hapticSuccess }) => {
      hapticSuccess("trade-imported")
    })
    notifyGettingStartedChecklistMaybeCompleted()
    dispatchGettingStartedSignalsRefresh()
    await refreshDashboardData()
  }, [closeImport, refreshDashboardData])

  useEffect(() => {
    auditLogDashboardMounted(user?.id ?? null)
  }, [user?.id])

  const hasSeenOnboardingCompletePopup =
    profile?.has_seen_onboarding_complete_popup === true ||
    checklistSignals.hasSeenOnboardingCompletePopup

  useEffect(() => {
    if (!user?.id) return

    const profileLoaded = profile != null
    const onboardingCompleted = profileLoaded
      ? profile.onboarding_completed === true
      : checklistSignals.onboardingCompleted
    // Mirrors the render gate: nothing mounts until the checklist signals are
    // resolved (fetched or restored from the session cache); trades cache can
    // only hide the card sooner via the max().
    const effectiveTradeCount = Math.max(
      checklistSignals.tradeCount,
      trades.length
    )

    const renderChecklist =
      checklistSignalsReady &&
      shouldAutoShowGettingStartedChecklist(user.id, {
        onboardingCompleted,
        allComplete: gettingStartedProgress.allComplete,
        hasSeenOnboardingCompletePopup,
        tradeCount: effectiveTradeCount,
      })

    auditLogDashboardDecision({
      source: "app/(app)/dashboard/page.tsx",
      onboardingResolved: checklistSignalsReady,
      onboardingCompleted,
      renderChecklist,
      reason: !checklistSignalsReady
        ? "waiting for checklist signals (fetch or session cache)"
        : !onboardingCompleted
          ? "profile onboarding incomplete"
          : effectiveTradeCount > 0
            ? "first trade logged — checklist moves to navbar"
            : gettingStartedProgress.allComplete ||
                hasSeenOnboardingCompletePopup
              ? "getting started complete or popup seen"
              : renderChecklist
                ? "active getting started — auto-show until first trade"
                : "session dismissed or no user",
    })
  }, [
    user?.id,
    profile,
    profileLoading,
    checklistSignalsReady,
    checklistSignals.onboardingCompleted,
    checklistSignals.hasSeenOnboardingCompletePopup,
    checklistSignals.tradeCount,
    gettingStartedProgress.allComplete,
    hasSeenOnboardingCompletePopup,
    trades.length,
  ])

  useEffect(() => {
    if (typeof window === "undefined") return
    const params = new URLSearchParams(window.location.search)
    if (params.get("checkout") !== "success") return

    if (user?.id) {
      markStripeReconciliationPending(user.id)
    }

    const url = new URL(window.location.href)
    url.searchParams.delete("checkout")
    window.history.replaceState({}, "", `${url.pathname}${url.search}`)
  }, [user?.id])

  useEffect(() => {
    if (typeof window === "undefined") return
    const params = new URLSearchParams(window.location.search)
    if (params.get("creator") !== "activated") return

    showPopup({
      type: "success",
      message: CREATOR_ACCESS_SUCCESS_MESSAGE,
      persist: true,
    })

    const url = new URL(window.location.href)
    url.searchParams.delete("creator")
    window.history.replaceState({}, "", `${url.pathname}${url.search}`)
  }, [showPopup])

  useEffect(() => {
    return subscribeStripeReconciliationComplete(() => {
      void (async () => {
        await refreshChecklistSignals({ fromUserAction: true })
        dispatchGettingStartedSignalsRefresh()
        void refreshDashboardData()
      })()
    })
  }, [refreshChecklistSignals, refreshDashboardData])

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      const node = e.target
      const el = node instanceof Element ? node : (node as Node).parentElement
      if (!el?.closest(".dashboard-controls")) {
        setShowControls(false)
      }
    }
    document.addEventListener("click", handleClick)
    return () => document.removeEventListener("click", handleClick)
  }, [])

  useEffect(() => {
    if (!showControls) {
      setGearDraft(null)
      setDdInputFocused(false)
      return
    }
    const raw = profile?.max_drawdown_limit
    setGearDraft({
      timeFilter,
      accountFilter,
      accountTypeFilter,
      showPublicOnly,
      showEquity,
      showDrawdown,
      showInsights,
      showSessions,
      showBestSetup,
      showWorstSetup,
      showWarnings,
      drawdownLimit:
        raw != null && String(raw) !== ""
          ? sanitizeDrawdownLimitInput(String(raw))
          : "",
    })
    // Snapshot when the panel opens only (avoid resetting drafts while editing).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [showControls])

  useEffect(() => {
    if (pageDataLoading || didHydrateDashboardPrefs.current) return
    didHydrateDashboardPrefs.current = true
    const p = loadDashboardGearPrefs()
    if (!p) return

    const {
      timeFilter: hydratedTimeFilter,
      accountFilter: hydratedAccountFilter,
      accountTypeFilter: hydratedAccountTypeFilter,
    } = sanitizeHydratedDashboardFilters({
      prefs: p,
      trades: tradesExcludingBacktest,
      accountRows,
      accountById,
      copyGroups,
    })

    setTimeFilter(hydratedTimeFilter)
    setAccountFilter(hydratedAccountFilter)
    setAccountTypeFilter(hydratedAccountTypeFilter)

    const filtersChanged =
      hydratedTimeFilter !== p.timeFilter ||
      hydratedAccountFilter !== p.accountFilter ||
      hydratedAccountTypeFilter !== p.accountTypeFilter

    if (typeof p.showPublicOnly === "boolean") setShowPublicOnly(p.showPublicOnly)
    if (typeof p.showEquity === "boolean") setShowEquity(p.showEquity)
    if (typeof p.showDrawdown === "boolean") setShowDrawdown(p.showDrawdown)
    if (typeof p.showInsights === "boolean") setShowInsights(p.showInsights)
    if (typeof p.showSessions === "boolean") setShowSessions(p.showSessions)
    if (typeof p.showBestSetup === "boolean") setShowBestSetup(p.showBestSetup)
    if (typeof p.showWorstSetup === "boolean") setShowWorstSetup(p.showWorstSetup)
    if (typeof p.showWarnings === "boolean") setShowWarnings(p.showWarnings)

    if (filtersChanged) {
      saveDashboardGearPrefs({
        timeFilter: hydratedTimeFilter,
        accountFilter: hydratedAccountFilter,
        accountTypeFilter: hydratedAccountTypeFilter,
        showPublicOnly:
          typeof p.showPublicOnly === "boolean" ? p.showPublicOnly : false,
        showEquity: typeof p.showEquity === "boolean" ? p.showEquity : true,
        showDrawdown: typeof p.showDrawdown === "boolean" ? p.showDrawdown : true,
        showInsights: typeof p.showInsights === "boolean" ? p.showInsights : true,
        showSessions: typeof p.showSessions === "boolean" ? p.showSessions : true,
        showBestSetup: typeof p.showBestSetup === "boolean" ? p.showBestSetup : true,
        showWorstSetup: typeof p.showWorstSetup === "boolean" ? p.showWorstSetup : true,
        showWarnings: typeof p.showWarnings === "boolean" ? p.showWarnings : true,
      })
    }
  }, [
    pageDataLoading,
    tradesExcludingBacktest,
    accountRows,
    accountById,
    copyGroups,
  ])

  // 🔥 MEMOIZED CALCULATIONS (PERFORMANCE BOOST)
  const {
    filteredTrades,
    totalTrades,
    winRate,
    totalPnL,
    avgRR,
    biggestLoss,
    bestTrade,
    avgWin,
    avgLoss,
    bestDay,
    worstDay,
    symbolPerformanceRows,
    longShortPerformance,
    holdTimeStats,
    maxDrawdown,
    sessionBuckets,
    bestSetup,
    insights,
    combinedInsights,
    worstInsight,
    warnings,
    equityDrawdownChartData,
    expectancyData,
    streakData,
    hourData,
    weekdayData,
    sessionPieData,
    insightBestSymbol,
    insightBestSymbolAvg,
    insightBestWeekday,
    insightBestWeekdayAvg,
    hasTradingDayTimeSource,
  } = useDashboardAnalytics({
    deferredTradesExcludingBacktest,
    showPublicOnly,
    accountFilter,
    accountTypeFilter,
    timeFilter,
    selectedDate,
    customRangeStart,
    customRangeEnd,
    accountById,
    copyGroupAccountIds,
  })

  useEffect(() => {
    if (accountFilter === "all") return
    if (!isValidAccountFilterValue(accountFilter, accounts, copyGroups)) {
      setAccountFilter("all")
    }
  }, [accounts, accountFilter, copyGroups])

  // 🔥 LOADING STATE (FIXES GLITCH)
  const showFreePlanAccountBanner = useMemo(() => {
    if (isPro || !tradesExcludingBacktest.length) return false
    const keys = new Set(
      tradesExcludingBacktest.map((t) =>
        [
          String(t.account_type ?? "").toLowerCase().trim(),
          String(t.account_size ?? "").trim(),
          String(t.account_id ?? "").trim(),
        ].join("-")
      )
    )
    return keys.size >= 1
  }, [tradesExcludingBacktest, isPro])

  const dashboardHasCachedData =
    user?.id != null && getCachedTrades(user.id) != null

  const analyticsPending =
    deferredTradesExcludingBacktest !== tradesExcludingBacktest
  const statsStillLoading =
    (pageDataLoading || analyticsPending) && !dashboardHasCachedData

  useEffect(() => {
    if (statsStillLoading) return
    if (deferredSectionsReady) return

    if ("requestIdleCallback" in window) {
      const idleId = window.requestIdleCallback(
        () => setDeferredSectionsReady(true),
        { timeout: 1200 }
      )
      return () => window.cancelIdleCallback(idleId)
    }

    const timeoutId = globalThis.setTimeout(
      () => setDeferredSectionsReady(true),
      0
    )
    return () => globalThis.clearTimeout(timeoutId)
  }, [deferredSectionsReady, statsStillLoading])

  const dashboardInteractive =
    user?.id != null && (!pageDataLoading || dashboardHasCachedData)

  usePrefetchSecondaryRoutesWhenReady(
    dashboardInteractive,
    profile
      ? profilePath(profile)
      : user?.id
        ? profilePath({ id: user.id })
        : null
  )

  const hasNoTrades =
    !statsStillLoading && tradesExcludingBacktest.length === 0

  const onboardingCompletedForAutoShow = profile
    ? profile.onboarding_completed === true
    : checklistSignals.onboardingCompleted
  const hasSeenOnboardingCompletePopupForAutoShow =
    profile?.has_seen_onboarding_complete_popup === true ||
    checklistSignals.hasSeenOnboardingCompletePopup

  // Trades cache only ever HIDES the card sooner (e.g. right after the first
  // trade is logged, before the signals refetch lands) — it never shows it.
  const tradeCountForAutoShow = Math.max(
    checklistSignals.tradeCount,
    trades.length
  )

  // The checklist mounts only once completion state is definitively known:
  // signals resolved by the fetch or restored from the per-user session cache.
  // While unresolved, render nothing — completed users must never see a flash.
  const showOnboardingSection =
    checklistSignalsReady &&
    shouldAutoShowGettingStartedChecklist(user?.id, {
      onboardingCompleted: onboardingCompletedForAutoShow,
      allComplete: gettingStartedProgress.allComplete,
      hasSeenOnboardingCompletePopup: hasSeenOnboardingCompletePopupForAutoShow,
      tradeCount: tradeCountForAutoShow,
    })

  const renderGettingStartedChecklist = (options?: {
    showWelcomeHeading?: boolean
  }) =>
    showOnboardingSection && user?.id ? (
      <GettingStartedChecklist
        progress={gettingStartedProgress}
        userId={user.id}
        profileId={user.id ?? profile?.id}
        firstPrivateTradeId={checklistSignals.firstPrivateTradeId}
        onChecklistRefresh={() => void refreshChecklistSignals()}
        defaultExpanded
        showWelcomeHeading={options?.showWelcomeHeading === true}
      />
    ) : null

  /** Desktop: dashboard card until first trade only. */
  const gettingStartedSection = (() => {
    const checklist = renderGettingStartedChecklist()
    return checklist ? (
      <div className="hidden md:block">{checklist}</div>
    ) : null
  })()

  /** Mobile: dashboard card until first trade only (then navbar entry). */
  const gettingStartedSectionMobile = (() => {
    const checklist = renderGettingStartedChecklist({
      showWelcomeHeading: true,
    })
    return checklist ? <div className="md:hidden">{checklist}</div> : null
  })()

  const currentStreak =
    streakData?.currentType === "loss"
      ? -Number(streakData.currentStreak || 0)
      : streakData?.currentType === "win"
        ? Number(streakData.currentStreak || 0)
        : 0

  const bestWinStreak = streakData?.maxWinStreak ?? 0

  const grossProfit = filteredTrades
    .filter((t) => (Number(t.pnl) || 0) > 0)
    .reduce((sum, t) => sum + (Number(t.pnl) || 0), 0)

  const grossLoss = filteredTrades
    .filter((t) => (Number(t.pnl) || 0) < 0)
    .reduce((sum, t) => sum + Math.abs(Number(t.pnl) || 0), 0)

  const profitFactor = grossLoss === 0 ? 0 : grossProfit / grossLoss

  const dailyMap: Record<string, number> = {}

  filteredTrades.forEach((t) => {
    const date = getDashboardTradingDayKey(t)
    if (!date) return

    if (!dailyMap[date]) {
      dailyMap[date] = 0
    }

    dailyMap[date] += Number(t.pnl) || 0
  })

  const dailyValues = Object.values(dailyMap)

  const avgDay =
    dailyValues.length > 0
      ? dailyValues.reduce((a, b) => a + b, 0) / dailyValues.length
      : 0

  const greenDays = dailyValues.filter((v) => v > 0).length

  const consistency =
    dailyValues.length > 0
      ? (greenDays / dailyValues.length) * 100
      : 0

  async function saveDashboardGearPanel() {
    if (isDemoModeActive()) {
      requestDemoSignup("save")
      return
    }
    if (!user || !gearDraft) return

    const rawLimit = finalizeDrawdownLimitInput(gearDraft.drawdownLimit).trim()
    const n =
      rawLimit === "" || rawLimit === "."
        ? null
        : Number(finalizeDrawdownLimitInput(gearDraft.drawdownLimit))
    if (
      rawLimit !== "" &&
      rawLimit !== "." &&
      (n === null || !Number.isFinite(n) || n < 0)
    ) {
      alert(
        "Enter a valid non-negative dollar amount for drawdown limit, or leave blank to clear."
      )
      return
    }

    setSavingGearSettings(true)
    const { error } = await supabase
      .from("profiles")
      .update({ max_drawdown_limit: n })
      .eq("id", user.id)
    setSavingGearSettings(false)

    if (error) {
      alert(toUserFacingErrorMessage(error))
      return
    }

    const { error: mirrorErr } = await mirrorAccountSettingsMaxDrawdownLimit(
      supabase,
      user.id,
      n
    )
    if (mirrorErr) {
      console.error("mirror account_settings.max_drawdown_limit:", mirrorErr)
    }

    const nextAccount = sanitizeDashboardAccountFilter(
      gearDraft.accountFilter,
      accounts,
      copyGroups
    )

    setTimeFilter(gearDraft.timeFilter)
    setAccountFilter(nextAccount)
    setAccountTypeFilter(gearDraft.accountTypeFilter)
    setShowPublicOnly(gearDraft.showPublicOnly)
    setShowEquity(gearDraft.showEquity)
    setShowDrawdown(gearDraft.showDrawdown)
    setShowInsights(gearDraft.showInsights)
    setShowSessions(gearDraft.showSessions)
    setShowBestSetup(gearDraft.showBestSetup)
    setShowWorstSetup(gearDraft.showWorstSetup)
    setShowWarnings(gearDraft.showWarnings)

    saveDashboardGearPrefs({
      timeFilter: gearDraft.timeFilter,
      accountFilter: nextAccount,
      accountTypeFilter: gearDraft.accountTypeFilter,
      showPublicOnly: gearDraft.showPublicOnly,
      showEquity: gearDraft.showEquity,
      showDrawdown: gearDraft.showDrawdown,
      showInsights: gearDraft.showInsights,
      showSessions: gearDraft.showSessions,
      showBestSetup: gearDraft.showBestSetup,
      showWorstSetup: gearDraft.showWorstSetup,
      showWarnings: gearDraft.showWarnings,
    })

    setProfile((p) => (p ? { ...p, max_drawdown_limit: n } : p))
    setShowControls(false)
  }

  function cancelDashboardGearPanel() {
    setShowControls(false)
  }

  const recentTradesList = useMemo(
    () =>
      (filteredTrades || [])
        .slice()
        .sort(
          (a, b) =>
            new Date(b.created_at as string).getTime() -
            new Date(a.created_at as string).getTime()
        )
        .slice(0, 5),
    [filteredTrades]
  )

  const handleSelectRecentTrade = useCallback(
    (trade: DashboardTradeRow) => {
      void import("@/lib/nativeHaptics").then(({ hapticLight }) => {
        hapticLight("open-trade")
      })
      setEditingTrade(trade)
    },
    [setEditingTrade]
  )

  const recentTradesSection = (
    <DashboardRecentTrades
      trades={recentTradesList}
      hasAnyTrades={tradesExcludingBacktest.length > 0}
      onSelectTrade={handleSelectRecentTrade}
    />
  )

  const dashboardUserIsPro = isProActive(profile)

  return (
    <>
      <FeedbackModal {...feedbackModalProps} />

      <NativeIosPullToRefresh onRefresh={refreshDashboardData}>
      <div className="w-full px-3 pb-3 pt-4 text-white md:px-10 md:pb-10 md:pt-0">

        <div className="relative z-50 mx-auto w-full max-w-[1600px] px-4 md:px-6">
          {!hasNoTrades && !statsStillLoading ? (
            <DashboardFilters
              isPro={isPro}
              accounts={accounts}
              accountFilter={accountFilter}
              onAccountChange={setAccountFilter}
              copyGroups={copyGroups}
              accountTypeFilter={accountTypeFilter}
              onAccountTypeChange={setAccountTypeFilter}
              timeframe={timeFilter}
              onTimeframeChange={handleDashboardTimeframeChange}
              customRangeStart={customRangeStart}
              customRangeEnd={customRangeEnd}
              onCustomRangeApply={handleDashboardCustomRangeApply}
              selectedDate={selectedDate}
              onSelectedDateChange={setSelectedDate}
              showPublicOnly={showPublicOnly}
              onTogglePublicOnly={() => setShowPublicOnly(!showPublicOnly)}
              onOpenPerformanceShare={() => {
                if (isDemoModeActive()) {
                  requestDemoSignup("upload")
                  return
                }
                if (!isPro) {
                  openExportUpgradeModal()
                  return
                }
                openPerformanceShare()
              }}
              onOpenQuickInput={() => {
                if (isDemoModeActive()) {
                  requestDemoSignup("trade")
                  return
                }
                openQuickTrade()
              }}
              showControls={showControls}
              onToggleShowControls={() => setShowControls((prev) => !prev)}
              gearDraft={gearDraft}
              setGearDraft={setGearDraft}
              ddInputFocused={ddInputFocused}
              setDdInputFocused={setDdInputFocused}
              savingGearSettings={savingGearSettings}
              hasUser={Boolean(user)}
              onSaveGear={() => void saveDashboardGearPanel()}
              onCancelGear={cancelDashboardGearPanel}
              showShareControls={totalTrades > 0}
              showTradingReportButton={Boolean(user?.id && dashboardUserIsPro && totalTrades > 0)}
              onOpenTradingReport={() => tradingReportsRef.current?.openReport()}
              showPropFirmLink={showPropFirmLink}
            />
          ) : null}
          <DashboardHeader
            showFreePlanAccountBanner={showFreePlanAccountBanner}
          />
        </div>

          <div className="relative z-0 mx-auto flex w-full max-w-[1600px] flex-col gap-2 overflow-visible px-4 md:gap-3 md:px-6">

  {/* Large Founding Challenge card only until the first trade; afterwards it
      stays reachable from the navbar Getting Started entry. */}
  {user?.id &&
  shouldShowProForLifeCard(profile) &&
  checklistSignalsReady &&
  checklistSignals.tradeCount === 0 ? (
    <div className="mt-4 md:mt-6">
      <TraxsProForLifeCard
        referralCode={profile?.referral_code}
        onAwarded={refreshProfile}
      />
    </div>
  ) : null}

  {gettingStartedSectionMobile}

  {statsStillLoading ? (
    <SkeletonDashboardShell />
  ) : hasNoTrades ? (
    <>
      {/* Desktop: match section gap (gap-2 / md:gap-3). Mobile: contents dissolves so layout stays unchanged. */}
      <div className="mt-2 flex flex-col gap-2 max-md:mt-0 max-md:contents md:gap-3">
        {(() => {
          const checklist = renderGettingStartedChecklist({
            showWelcomeHeading: true,
          })
          return checklist ? (
            <div className="hidden md:block">{checklist}</div>
          ) : null
        })()}
        <div className="rounded-xl border border-white/10 bg-white/5 px-5 pb-4 pt-3.5 backdrop-blur-md md:px-6 md:pb-5 md:pt-4">
          <p className="max-w-2xl text-sm font-medium text-gray-200 md:text-base">
            Get started by logging your first trade or importing your trading history.
          </p>
          <div className="mt-3 flex flex-wrap items-center gap-2 md:mt-3.5 md:gap-3">
            <Link
              href="/app"
              className="inline-flex min-h-[44px] items-center rounded-lg bg-blue-500 px-3.5 py-2 text-xs font-semibold text-white transition hover:bg-blue-600 md:px-4 md:text-sm disabled:hover:bg-blue-500"
            >
              Add Trade
            </Link>
            <button
              type="button"
              onClick={() => {
                if (isDemoModeActive()) {
                  requestDemoSignup("save")
                  return
                }
                openImport()
              }}
              className="inline-flex min-h-[44px] items-center rounded-lg border border-white/20 bg-white/10 px-3.5 py-2 text-xs font-semibold text-white transition hover:bg-white/15 md:px-4 md:text-sm"
            >
              Import CSV
            </button>
          </div>
          <div className="mt-2 md:mt-2.5">
            <div className="mb-2.5 h-px w-16 bg-white/10 md:mb-3" aria-hidden />
            <p className="text-xs font-medium text-gray-200">
              After your first trade you&apos;ll unlock:
            </p>
            <ul className="mt-1.5 space-y-1 text-xs text-gray-400">
              <li>• Performance statistics</li>
              <li>• Equity curve tracking</li>
              <li>• Session &amp; weekday analysis</li>
              <li>• Symbol performance insights</li>
            </ul>
          </div>
        </div>
      </div>
    </>
  ) : totalTrades === 0 ? (
    <>
      {gettingStartedSection}
      <EmptyState
        title="No trades match your filters"
        description="Try adjusting your account, mode, timeframe, or date filters to see your trades."
        className="rounded-xl border border-white/10 bg-white/5 py-12 backdrop-blur-md"
      />
    </>
  ) : (
    <>
      {gettingStartedSection}
      {dashboardUserIsPro ? (
        <>
      {user?.id && deferredSectionsReady ? (
        <DashboardTradingReports
          ref={tradingReportsRef}
          userId={user.id}
          trades={tradesExcludingBacktest}
          onViewTrade={handleSelectRecentTrade}
        />
      ) : null}
  <DashboardCharts
    isPro
    deferredSectionsReady={deferredSectionsReady}
    equityData={equityDrawdownChartData}
    weekdayData={weekdayData}
    sessionPieData={sessionPieData}
    sessionBuckets={sessionBuckets}
    maxDrawdown={maxDrawdown}
    showDrawdown={showDrawdown}
    currentStreak={currentStreak}
    avgDay={avgDay}
    consistency={consistency}
    recentTrades={recentTradesSection}
    totalTrades={totalTrades}
    winRate={winRate}
    avgRR={avgRR}
    totalPnL={totalPnL}
    profitFactor={profitFactor}
    avgWin={avgWin}
    bestTrade={bestTrade}
    avgLoss={avgLoss}
    biggestLoss={biggestLoss}
    bestDay={bestDay}
    worstDay={worstDay}
    showEquity={showEquity}
    expectancyData={expectancyData}
    streakData={streakData}
    hourData={hourData}
    showSessions={showSessions}
    bestWinStreak={bestWinStreak}
  />

  {!deferredSectionsReady ? (
    <DashboardDeferredSectionsSkeleton />
  ) : (
  <>
  <DashboardAnalytics
    symbolPerformanceRows={symbolPerformanceRows}
    hasAnyTrades={tradesExcludingBacktest.length > 0}
    deferredSectionsReady={deferredSectionsReady}
    weekdayData={weekdayData}
    longShortPerformance={longShortPerformance}
    holdTimeStats={holdTimeStats}
    totalTrades={totalTrades}
  />

          <DashboardInsights
            showInsights={showInsights}
            showBestSetup={showBestSetup}
            showWorstSetup={showWorstSetup}
            showWarnings={showWarnings}
            totalTrades={totalTrades}
            hasTradingDayTimeSource={hasTradingDayTimeSource}
            insights={insights}
            combinedInsights={combinedInsights}
            worstInsight={worstInsight}
            warnings={warnings}
            insightBestSymbol={insightBestSymbol}
            insightBestSymbolAvg={insightBestSymbolAvg}
            insightBestWeekday={insightBestWeekday}
            insightBestWeekdayAvg={insightBestWeekdayAvg}
            bestSetup={bestSetup}
          />

          <div className="md:hidden">{recentTradesSection}</div>
  </>
  )}
        </>
      ) : (
        <>
          <DashboardCharts
            isPro={false}
            deferredSectionsReady={deferredSectionsReady}
            equityData={equityDrawdownChartData}
            weekdayData={weekdayData}
            sessionPieData={sessionPieData}
            sessionBuckets={sessionBuckets}
            maxDrawdown={maxDrawdown}
            showDrawdown={showDrawdown}
            currentStreak={currentStreak}
            avgDay={avgDay}
            consistency={consistency}
            recentTrades={recentTradesSection}
            totalTrades={totalTrades}
            winRate={winRate}
            avgRR={avgRR}
            totalPnL={totalPnL}
            profitFactor={profitFactor}
            avgWin={avgWin}
            bestTrade={bestTrade}
            avgLoss={avgLoss}
            biggestLoss={biggestLoss}
            bestDay={bestDay}
            worstDay={worstDay}
            showEquity={showEquity}
            expectancyData={expectancyData}
            streakData={streakData}
            hourData={hourData}
            showSessions={showSessions}
            bestWinStreak={bestWinStreak}
          />
          {recentTradesSection}
          {deferredSectionsReady ? (
            <DashboardPremiumPreviewSection />
          ) : (
            <DashboardDeferredSectionsSkeleton />
          )}
        </>
      )}
    </>
  )}

          </div>
      </div>
      </NativeIosPullToRefresh>

      <DashboardModals
        importOpen={showImportModal}
        onImportComplete={() => void handleImportModalComplete()}
        performanceShareOpen={showPerformanceShare}
        onClosePerformanceShare={closePerformanceShare}
        performanceShareTrades={tradesForPerformanceSharePool}
        profile={profile}
        customRangeStart={customRangeStart}
        customRangeEnd={customRangeEnd}
        upgradeOpen={showProUpgradeModal}
        onCloseUpgrade={closeUpgrade}
        quickTradeOpen={showQuickTrade}
        userId={user?.id ?? null}
        onCloseQuickTrade={closeQuickTrade}
        selectedImage={selectedImage}
        editingTrade={editingTrade}
        sendTradeId={sendTradeId}
        onCloseImage={closeImage}
        onCloseTrade={closeTrade}
        onCloseSend={closeSend}
      />
    </>
  )
}
