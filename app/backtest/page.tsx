"use client"

import "../analyticsDesktopTheme.css"
import "./backtestLabTheme.css"
import dynamic from "next/dynamic"
import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "@/lib/supabase"
import { deleteUserTrade } from "@/lib/deleteTrade"
import EntitlementStatusNotice from "@/app/components/monetization/EntitlementStatusNotice"
import LockedFeature from "../components/LockedFeature"
import { useProGate } from "@/lib/useProGate"
import Calendar from "@/components/Calendar"
import { ConfirmModal, useDeleteTradeConfirmation } from "../components/ui"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { isDemoSupabaseBlocked } from "@/lib/demo/demoSupabaseGuard"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import { tradeAnalysisHref } from "@/lib/tradeAnalysisNavigation"
import { getDemoBacktestTrades } from "@/lib/demo/demoBacktest"
import { DEMO_PROFILE } from "@/lib/demo/fixtures"
import { rpcTradesOwnerRows } from "@/lib/tradeOwnerRead"
import { mapProjectedRows } from "@/lib/supabaseProjectedQuery"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { SkeletonBacktestPageContent } from "../components/ui/skeletons"
import ImageLightbox from "../components/ui/ImageLightbox"
import BacktestLabStatsGrid from "@/app/components/backtest/BacktestLabStatsGrid"
import BacktestLabStrategyLeaderboard from "@/app/components/backtest/BacktestLabStrategyLeaderboard"
import BacktestLabStrategyComparisonChart from "@/app/components/backtest/BacktestLabStrategyComparisonChart"
import BacktestLabInstrumentTable from "@/app/components/backtest/BacktestLabInstrumentTable"
import BacktestLabReportSection from "@/app/components/backtest/BacktestLabReportSection"
import BacktestLabReviewSection from "@/app/components/backtest/BacktestLabReviewSection"
import BacktestLabTabs, {
  backtestLabTabPanelId,
  type BacktestLabTab,
} from "@/app/components/backtest/BacktestLabTabs"
import BacktestLabToolbar, {
  buildBacktestAccountFilterOptions,
} from "@/app/components/backtest/BacktestLabToolbar"
import BacktestLabEquityCurve from "@/app/components/backtest/BacktestLabEquityCurve"
import {
  applyBacktestLabFilters,
  BACKTEST_LAB_FILTER_ALL,
  computeTradeExpectancy,
  distinctBacktestStrategyGroups,
  distinctBacktestTickers,
  formatBacktestLabFilterDateRangeLabel,
  normalizeBacktestLabFilterDate,
  pickDefaultBacktestAccountId,
  selectBacktestTrades,
  type BacktestLabFilterState,
} from "@/lib/backtestLabFilters"
import {
  buildBacktestInstrumentLeaderboard,
  buildBacktestStrategyLeaderboard,
} from "@/lib/backtestLabAnalytics"
import { buildBacktestLabEquityChartData } from "@/lib/backtestLabEquityCurve"
import { compareDashboardTradesChronological } from "@/lib/dashboardTradeDate"
import { computeMaxDrawdown } from "@/lib/dashboardMaxDrawdown"
import { computePeriodTradeStats } from "@/lib/periodTradeStats"
import { ensureAccountsLoaded, getCachedAccounts } from "@/lib/appDataCache"
import {
  backtestStrategyPresetLabels,
  canonicalBacktestStrategyLabel,
  isBacktestTradeNeedsReview,
} from "@/lib/backtestLabReview"
import { updateBacktestTradeReviewed } from "@/lib/backtestLabReviewActions"
import { useToast } from "@/app/components/ui"

const InputTradeForm = dynamic(() => import("../components/InputTradeForm"), {
  ssr: false,
})
const PerformanceShareModal = dynamic(
  () => import("../components/PerformanceShareModal"),
  { ssr: false }
)

type BacktestTrade = Record<string, unknown> & {
  id: string
  strategy?: string | null
  pnl?: number | null
  rr?: number | null
  created_at: string
}

const DEFAULT_FILTERS: BacktestLabFilterState = {
  accountId: BACKTEST_LAB_FILTER_ALL,
  strategy: BACKTEST_LAB_FILTER_ALL,
  ticker: BACKTEST_LAB_FILTER_ALL,
  dateStart: "",
  dateEnd: "",
  result: "all",
  review: "all",
  documentation: "all",
}

export default function BacktestPage() {
  const router = useRouter()
  const toast = useToast()
  const { user, profile: contextProfile } = useUserProfile()
  const {
    access,
    proFeatureUnlocked,
    shouldGateFeature,
    presentFeature,
    entitlementStatus,
    refreshEntitlement,
  } = useProGate(contextProfile)
  const [allBacktestTrades, setAllBacktestTrades] = useState<BacktestTrade[]>(
    []
  )
  const [accounts, setAccounts] = useState<Record<string, unknown>[]>([])
  const [loading, setLoading] = useState(true)
  const [filters, setFilters] = useState<BacktestLabFilterState>(DEFAULT_FILTERS)
  const [editingTrade, setEditingTrade] = useState<BacktestTrade | null>(null)
  const [showLogTrade, setShowLogTrade] = useState(false)
  const [selectedImage, setSelectedImage] = useState<string | null>(null)
  const [showPerformanceShare, setShowPerformanceShare] = useState(false)
  const [proLocked, setProLocked] = useState(false)
  const [shareProfile, setShareProfile] = useState<{
    referral_code?: string | null
  } | null>(null)
  const [activeTab, setActiveTab] = useState<BacktestLabTab>("overview")
  const [tradesViewMode, setTradesViewMode] = useState<"list" | "groups">(
    "list"
  )
  const [reviewBusyId, setReviewBusyId] = useState<string | null>(null)

  const loadBacktests = useCallback(async () => {
    if (isDemoModeActive() && user?.id) {
      setShareProfile({ referral_code: DEMO_PROFILE.referral_code })
      setAllBacktestTrades(getDemoBacktestTrades() as BacktestTrade[])
      setAccounts([])
      setProLocked(false)
      setLoading(false)
      return
    }

    if (!user?.id) {
      router.push("/login")
      setLoading(false)
      return
    }

    if (proFeatureUnlocked) {
      setProLocked(false)
      setShareProfile(
        contextProfile?.referral_code != null
          ? { referral_code: contextProfile.referral_code }
          : null
      )
    } else if (shouldGateFeature(true)) {
      setProLocked(true)
      setLoading(false)
      return
    } else {
      setProLocked(false)
      setShareProfile(
        contextProfile?.referral_code != null
          ? { referral_code: contextProfile.referral_code }
          : null
      )
    }

    const [{ rows }, accountRows] = await Promise.all([
      rpcTradesOwnerRows(supabase),
      getCachedAccounts(user.id) ??
        ensureAccountsLoaded(supabase, user.id).catch(() => []),
    ])

    const backtestRows = selectBacktestTrades(rows).sort(
      (a, b) => -compareDashboardTradesChronological(a, b)
    )

    setAllBacktestTrades(
      mapProjectedRows(backtestRows, (row) => row as BacktestTrade)
    )
    setAccounts(Array.isArray(accountRows) ? accountRows : [])
    setLoading(false)
  }, [
    user?.id,
    contextProfile?.referral_code,
    proFeatureUnlocked,
    router,
    shouldGateFeature,
  ])

  useEffect(() => {
    if (isDemoModeActive() && !user?.id) return
    if (access === "unknown") return
    void loadBacktests()
  }, [user?.id, access, proFeatureUnlocked, loadBacktests])

  const filteredTrades = useMemo(
    () => applyBacktestLabFilters(allBacktestTrades, filters),
    [allBacktestTrades, filters]
  )

  const strategyGroups = useMemo(
    () => distinctBacktestStrategyGroups(allBacktestTrades),
    [allBacktestTrades]
  )

  const analyticsTrades = useMemo(
    () =>
      applyBacktestLabFilters(allBacktestTrades, filters, {
        omitStrategy: true,
      }),
    [allBacktestTrades, filters]
  )

  const strategyLeaderboardRows = useMemo(
    () => buildBacktestStrategyLeaderboard(analyticsTrades, strategyGroups),
    [analyticsTrades, strategyGroups]
  )

  const instrumentLeaderboardRows = useMemo(
    () => buildBacktestInstrumentLeaderboard(analyticsTrades),
    [analyticsTrades]
  )

  const reportDateRangeLabel = useMemo(
    () => formatBacktestLabFilterDateRangeLabel(filters),
    [filters]
  )

  const selectedStrategyKey =
    filters.strategy === BACKTEST_LAB_FILTER_ALL ? null : filters.strategy

  const tickerOptions = useMemo(
    () => distinctBacktestTickers(allBacktestTrades),
    [allBacktestTrades]
  )

  const accountFilterOptions = useMemo(
    () => buildBacktestAccountFilterOptions(allBacktestTrades, accounts),
    [allBacktestTrades, accounts]
  )

  const defaultBacktestAccountId = useMemo(
    () => pickDefaultBacktestAccountId(accounts),
    [accounts]
  )

  const periodStats = useMemo(
    () => computePeriodTradeStats(filteredTrades),
    [filteredTrades]
  )

  const expectancy = useMemo(
    () => computeTradeExpectancy(filteredTrades),
    [filteredTrades]
  )

  const maxDrawdown = useMemo(
    () => computeMaxDrawdown(filteredTrades),
    [filteredTrades]
  )

  const equityChartData = useMemo(
    () => buildBacktestLabEquityChartData(filteredTrades),
    [filteredTrades]
  )

  const strategyPresetLabels = useMemo(
    () => backtestStrategyPresetLabels(strategyGroups),
    [strategyGroups]
  )

  const normalizeStrategyValue = useCallback(
    (raw: string) => canonicalBacktestStrategyLabel(raw, strategyGroups),
    [strategyGroups]
  )

  const needsReviewCount = useMemo(
    () =>
      allBacktestTrades.filter((t) => isBacktestTradeNeedsReview(t)).length,
    [allBacktestTrades]
  )

  const handleToggleReviewed = useCallback(
    async (tradeId: string, reviewed: boolean) => {
      if (isDemoSupabaseBlocked()) {
        setAllBacktestTrades((prev) =>
          prev.map((t) => (t.id === tradeId ? { ...t, reviewed } : t))
        )
        return
      }
      if (!user?.id) return
      setReviewBusyId(tradeId)
      const result = await updateBacktestTradeReviewed(
        supabase,
        tradeId,
        user.id,
        reviewed
      )
      setReviewBusyId(null)
      if (!result.ok) {
        toast.error("Could not update review status.")
        return
      }
      setAllBacktestTrades((prev) =>
        prev.map((t) => (t.id === tradeId ? { ...t, reviewed } : t))
      )
    },
    [user?.id, toast]
  )

  const performDeleteTrade = useCallback(async (id: string) => {
    if (isDemoSupabaseBlocked()) {
      requestDemoSignup("delete")
      return
    }
    await deleteUserTrade(supabase, id)
    setAllBacktestTrades((prev) => prev.filter((t) => t.id !== id))
  }, [])

  const handleEditTrade = useCallback((trade: Record<string, unknown>) => {
    if (isDemoSupabaseBlocked()) {
      requestDemoSignup("edit")
      return
    }
    setEditingTrade(trade as BacktestTrade)
  }, [])

  const handleSendTrade = useCallback((_trade: Record<string, unknown>) => {
    if (isDemoSupabaseBlocked()) {
      requestDemoSignup("trade")
    }
  }, [])

  const handleAnalyzeTrade = useCallback(
    (trade: Record<string, unknown>) => {
      if (isDemoModeActive()) {
        requestDemoSignup("ai")
        return
      }
      router.push(tradeAnalysisHref(String(trade.id)))
    },
    [router]
  )

  const { requestDelete: deleteTrade, confirmModalProps } =
    useDeleteTradeConfirmation(performDeleteTrade)

  const openLogBacktestTrade = useCallback(() => {
    if (isDemoSupabaseBlocked()) {
      requestDemoSignup("save")
      return
    }
    setShowLogTrade(true)
  }, [])

  if (access === "unknown") {
    return (
      <div className="tt-phase3-dark min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100">
        <div className="mx-auto max-w-lg px-6 py-10">
          <EntitlementStatusNotice
            status={entitlementStatus}
            onRetry={() => void refreshEntitlement()}
          />
        </div>
      </div>
    )
  }

  if (proLocked) {
    return (
      <>
        <div className="tt-phase3-dark min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100">
          <div className="mx-auto max-w-7xl px-6 pb-6 pt-6 xl:max-w-[1560px]">
            <LockedFeature
              title="Backtest Lab"
              feature="backtest_lab"
              className="mx-auto max-w-lg"
              onUpgradeClick={() => presentFeature("backtest_lab")}
            />
          </div>
        </div>
      </>
    )
  }

  return (
    <>
      <div className="tt-phase3-dark tt-backtest-lab min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100">
        <div className="mx-auto max-w-7xl px-4 pb-6 pt-3 sm:px-6 xl:max-w-[1560px]">
          <h1 className="mb-1 mt-0 text-center text-xl font-semibold text-blue-300 md:text-2xl">
            Backtest Lab
          </h1>
          <p className="mb-4 text-center text-sm text-[var(--tt-bl-control-muted,#9ca3af)]">
            Isolated backtests — does not affect dashboard or live trade history.
          </p>

          <BacktestLabToolbar
            filters={filters}
            onFiltersChange={setFilters}
            accountOptions={accountFilterOptions}
            strategyGroups={strategyGroups}
            tickerOptions={tickerOptions}
            onLogTrade={openLogBacktestTrade}
            onShare={() => setShowPerformanceShare(true)}
          />

          {loading ? (
            <SkeletonBacktestPageContent />
          ) : (
            <>
              <BacktestLabTabs
                value={activeTab}
                onChange={setActiveTab}
                needsReviewCount={needsReviewCount}
              />

              {activeTab === "overview" ? (
                <div
                  id={backtestLabTabPanelId("overview")}
                  role="tabpanel"
                  className="space-y-5"
                >
                  <BacktestLabStatsGrid
                    periodStats={periodStats}
                    expectancy={expectancy}
                    maxDrawdown={maxDrawdown}
                  />

                  <BacktestLabEquityCurve
                    data={equityChartData}
                    isPro={proFeatureUnlocked}
                    totalTrades={periodStats.totalTrades}
                    profitFactor={
                      periodStats.profitFactorInfinite
                        ? null
                        : periodStats.profitFactor
                    }
                    onLogTrade={openLogBacktestTrade}
                  />

                  <BacktestLabReportSection
                    trades={filteredTrades}
                    dateRangeLabel={reportDateRangeLabel}
                    viewerUserId={user?.id}
                  />
                </div>
              ) : null}

              {activeTab === "strategies" ? (
                <div
                  id={backtestLabTabPanelId("strategies")}
                  role="tabpanel"
                  className="space-y-2"
                >
                  <BacktestLabStrategyLeaderboard
                    rows={strategyLeaderboardRows}
                    selectedStrategyKey={selectedStrategyKey}
                    onSelectStrategy={(key) => {
                      setFilters((prev) => ({ ...prev, strategy: key }))
                      setActiveTab("trades")
                    }}
                  />

                  <BacktestLabStrategyComparisonChart
                    strategyRows={strategyLeaderboardRows}
                  />

                  <BacktestLabInstrumentTable rows={instrumentLeaderboardRows} />
                </div>
              ) : null}

              {activeTab === "calendar" ? (
                <div id={backtestLabTabPanelId("calendar")} role="tabpanel">
                  <h2 className="backtest-lab-section-title text-base md:text-lg">
                    Backtest calendar
                  </h2>
                  <Calendar trades={filteredTrades as any} />
                </div>
              ) : null}

              {activeTab === "trades" ? (
                <div id={backtestLabTabPanelId("trades")} role="tabpanel">
                  <BacktestLabReviewSection
                    trades={filteredTrades}
                    filters={filters}
                    onFiltersChange={setFilters}
                    strategyGroups={strategyGroups}
                    shareProfile={shareProfile}
                    onEdit={handleEditTrade}
                    onDelete={(id) => void deleteTrade(id)}
                    onSendClick={handleSendTrade}
                    onAnalyze={handleAnalyzeTrade}
                    onImageClick={(url) => setSelectedImage(url)}
                    onToggleReviewed={(id, reviewed) =>
                      void handleToggleReviewed(id, reviewed)
                    }
                    reviewBusyId={reviewBusyId}
                    viewMode={tradesViewMode}
                    onViewModeChange={setTradesViewMode}
                  />
                </div>
              ) : null}
            </>
          )}
        </div>
      </div>

      <ImageLightbox
        imageUrl={selectedImage}
        onClose={() => setSelectedImage(null)}
      />

      {showLogTrade ? (
        <InputTradeForm
          key="backtest-log-new"
          initialAccountId={defaultBacktestAccountId}
          openAsModal
          modalTitle="Log Backtest Trade"
          strategySuggestions={strategyPresetLabels}
          normalizeStrategyValue={normalizeStrategyValue}
          createAsUnreviewed
          accountPickerScope="backtest_only"
          onClose={() => setShowLogTrade(false)}
          onSave={() => {
            if (isDemoSupabaseBlocked()) {
              requestDemoSignup("save")
              setShowLogTrade(false)
              return
            }
            void loadBacktests()
            setShowLogTrade(false)
          }}
        />
      ) : null}

      {editingTrade ? (
        <InputTradeForm
          key={String(editingTrade.id)}
          existingTrade={editingTrade}
          strategySuggestions={strategyPresetLabels}
          normalizeStrategyValue={normalizeStrategyValue}
          accountPickerScope="backtest_only"
          onClose={() => setEditingTrade(null)}
          onSave={() => {
            if (isDemoSupabaseBlocked()) {
              requestDemoSignup("save")
              setEditingTrade(null)
              return
            }
            void loadBacktests()
            setEditingTrade(null)
          }}
        />
      ) : null}

      <PerformanceShareModal
        open={showPerformanceShare}
        onClose={() => setShowPerformanceShare(false)}
        tradePool={filteredTrades as any[]}
        subtitle="Backtest Lab · current filters"
        profile={shareProfile}
        initialCustomRangeStart={normalizeBacktestLabFilterDate(filters.dateStart)}
        initialCustomRangeEnd={normalizeBacktestLabFilterDate(filters.dateEnd)}
      />
      <ConfirmModal {...confirmModalProps} />
    </>
  )
}
