"use client"

import { filterTradesForPerformanceSharePool } from "@/lib/performanceShare"
import { excludeBacktestTrades } from "@/lib/tradeModeFilters"
import { averageRrFromTrades } from "@/lib/tradeRr"
import { useCallback, useEffect, useMemo, useState } from "react"
import { supabase } from "../../../lib/supabaseClient"
import NativeIosPullToRefresh from "@/app/components/NativeIosPullToRefresh"
import { deleteUserTrade } from "@/lib/deleteTrade"
import {
  buildAccountFilterOptionsFromRows,
} from "@/lib/tradeAccountDisplay"
import { useRouter } from "next/navigation"
import dynamic from "next/dynamic"
import TradesPageMainContent from "../../components/TradesPageMainContent"
import TradesPageOverlays from "../../components/TradesPageOverlays"
import ReelViewer from "../../components/profile/ReelViewer"
import { ConfirmModal, useDeleteTradeConfirmation } from "../../components/ui"
import { fetchReelsByTradeIds, type ReelRow } from "@/lib/reels"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { useCachedAccounts, useCachedTrades } from "@/lib/useAppDataCache"
import { getCachedAccounts, getCachedTrades } from "@/lib/appDataCache"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import { isProActive } from "@/lib/subscription"
import { useCopyTradingGroups } from "@/lib/useCopyTradingGroups"
import {
  isValidAccountFilterValue,
  resolveCopyGroupAccountIdsForFilter,
} from "@/lib/tradeAccountSelection"
import { tradeAnalysisHref } from "@/lib/tradeAnalysisNavigation"
import ProUpgradeModal from "../../components/ProUpgradeModal"
import PlatformTradesHeader from "@/app/components/platform/PlatformTradesHeader"
import {
  sortTradesForDisplay,
  type TradesSortKey,
} from "@/lib/tradesSort"
import { useIsNativeIos } from "@/lib/useIsNativeIos"

const QuickTradeModal = dynamic(
  () => import("../../components/QuickTradeModal"),
  { ssr: false }
)

export default function TradesPage() {
  const { user, profile: gateProfile, loading: profileLoading } = useUserProfile()
  const nativeIos = useIsNativeIos()
  const { trades: cachedTrades, loading: tradesLoading, refresh: refreshTrades } =
    useCachedTrades(user?.id, { fullHistory: true })
  const {
    accounts: accountRows,
    loading: accountsLoading,
    refresh: refreshAccounts,
  } = useCachedAccounts(user?.id)
  const trades = useMemo(
    () => excludeBacktestTrades(cachedTrades),
    [cachedTrades]
  )
  const tradesHasCachedData =
    user?.id != null && getCachedTrades(user.id) != null
  const accountsHasCachedData =
    user?.id != null && getCachedAccounts(user.id) != null

  const loading =
    (profileLoading && !gateProfile) ||
    (tradesLoading && cachedTrades.length === 0 && !tradesHasCachedData) ||
    (accountsLoading && accountRows.length === 0 && !accountsHasCachedData)

  const isPro = isProActive(gateProfile)
  const { copyGroups } = useCopyTradingGroups(user?.id, isPro)

  const [resultFilter, setResultFilter] = useState<"all" | "wins" | "losses">("all")
  const [selectedImage, setSelectedImage] = useState<string | null>(null)
  const [accountFilter, setAccountFilter] = useState("all")
  const [accountTypeFilter, setAccountTypeFilter] = useState("all")
  const [showPublicOnly, setShowPublicOnly] = useState(false)
  const [showAdvanced, setShowAdvanced] = useState(false)
  const [timeframe, setTimeframe] = useState("all")
  const [customRangeStart, setCustomRangeStart] = useState("")
  const [customRangeEnd, setCustomRangeEnd] = useState("")
  const [selectedDate, setSelectedDate] = useState("")
  const [editingTrade, setEditingTrade] = useState<any | null>(null)
  const [showPerformanceShare, setShowPerformanceShare] = useState(false)
  const [showQuickTrade, setShowQuickTrade] = useState(false)
  const [showExportUpgradeModal, setShowExportUpgradeModal] = useState(false)
  const [sendTradeId, setSendTradeId] = useState<string | null>(null)
  const [visibleCount, setVisibleCount] = useState(10)
  const [sortBy, setSortBy] = useState<TradesSortKey>("newest")
  const [tradeReelsByTradeId, setTradeReelsByTradeId] = useState<
    Record<string, ReelRow>
  >({})
  const [selectedReplay, setSelectedReplay] = useState<ReelRow | null>(null)
  const router = useRouter()

  const accountById = useMemo(() => {
    const m: Record<string, any> = {}
    accountRows.forEach((acc) => {
      m[String(acc.id)] = acc
    })
    return m
  }, [accountRows])

  useEffect(() => {
    if (!profileLoading && !user && !isDemoModeActive()) {
      router.push("/login")
    }
  }, [profileLoading, user, router])

  useEffect(() => {
    setVisibleCount(10)
  }, [timeframe, accountFilter, accountTypeFilter, resultFilter, sortBy])

  useEffect(() => {
    if (trades.length === 0) {
      setTradeReelsByTradeId({})
      return
    }

    let cancelled = false
    const tradeIds = trades
      .map((trade) => String(trade.id))
      .filter((id) => id.trim() !== "")

    void fetchReelsByTradeIds(supabase, tradeIds).then((map) => {
      if (cancelled) return
      const record: Record<string, ReelRow> = {}
      map.forEach((reel, tradeId) => {
        record[tradeId] = reel
      })
      setTradeReelsByTradeId(record)
    })

    return () => {
      cancelled = true
    }
  }, [trades])

  useEffect(() => {
    if (typeof window === "undefined" || loading || trades.length === 0) return

    const editId = new URLSearchParams(window.location.search).get("edit")?.trim()
    if (!editId) return

    if (isDemoModeActive()) {
      requestDemoSignup("edit")
      return
    }

    const trade = trades.find((t) => String(t.id) === editId)
    if (!trade) return

    // Keep the same object while the modal is open so trade-cache refreshes
    // do not wipe in-progress edits via InputTradeForm hydration.
    setEditingTrade((prev) =>
      prev && String(prev.id) === editId ? prev : { ...trade }
    )
  }, [loading, trades])

  const handleEditTrade = useCallback((trade: any) => {
    if (isDemoModeActive()) {
      requestDemoSignup("edit")
      return
    }
    void import("@/lib/nativeHaptics").then(({ hapticLight }) => {
      hapticLight("open-trade")
    })
    setEditingTrade({ ...trade })
  }, [])

  const performDeleteTrade = useCallback(
    async (id: string) => {
      if (isDemoModeActive()) {
        requestDemoSignup("delete")
        return
      }
      await deleteUserTrade(supabase, id, { userId: user?.id })
    },
    [user?.id]
  )

  const { requestDelete: handleDeleteTrade, confirmModalProps } =
    useDeleteTradeConfirmation(performDeleteTrade)

  const handleSendTrade = useCallback((trade: any) => {
    if (isDemoModeActive()) {
      requestDemoSignup("trade")
      return
    }
    setSendTradeId(String(trade.id))
  }, [])

  const handleOpenTradeReplay = useCallback(
    (trade: any) => {
      const reel = tradeReelsByTradeId[String(trade.id)]
      if (reel) setSelectedReplay(reel)
    },
    [tradeReelsByTradeId]
  )

  const handleAnalyzeTrade = useCallback(
    (trade: any) => {
      if (isDemoModeActive()) {
        requestDemoSignup("ai")
        return
      }
      router.push(tradeAnalysisHref(trade.id))
    },
    [router]
  )

  const handleImageClick = useCallback((url: string) => {
    setSelectedImage(url)
  }, [])

  const handleCloseImageLightbox = useCallback(() => {
    setSelectedImage(null)
  }, [])

  const handleCloseEditForm = useCallback(() => {
    setEditingTrade(null)
    if (typeof window !== "undefined") {
      const url = new URL(window.location.href)
      if (url.searchParams.has("edit")) {
        url.searchParams.delete("edit")
        const next = url.search ? `${url.pathname}${url.search}` : url.pathname
        router.replace(next, { scroll: false })
      }
    }
  }, [router])

  const handleClosePerformanceShare = useCallback(() => {
    setShowPerformanceShare(false)
  }, [])

  const handleCloseSendModal = useCallback(() => {
    setSendTradeId(null)
  }, [])

  const handleOpenPerformanceShare = useCallback(() => {
    if (isDemoModeActive()) {
      requestDemoSignup("upload")
      return
    }
    if (!isProActive(gateProfile)) {
      setShowExportUpgradeModal(true)
      return
    }
    setShowPerformanceShare(true)
  }, [gateProfile])

  const handleToggleAdvanced = useCallback(() => {
    setShowAdvanced((prev) => !prev)
  }, [])

  const handleTogglePublicOnly = useCallback(() => {
    setShowPublicOnly((prev) => !prev)
  }, [])

  const handleLoadMore = useCallback(() => {
    setVisibleCount((prev) => prev + 10)
  }, [])

  const handleOpenQuickInput = useCallback(() => {
    if (isDemoModeActive()) {
      requestDemoSignup("trade")
      return
    }
    setShowQuickTrade(true)
  }, [])

  const handleTradeFormSaved = useCallback(() => {
    if (isDemoModeActive()) {
      requestDemoSignup("save")
      return
    }
    setEditingTrade(null)
  }, [])

  const handleTimeframeChange = useCallback((value: string) => {
    setTimeframe(value)
    if (value !== "custom") {
      setCustomRangeStart("")
      setCustomRangeEnd("")
    }
  }, [])

  const handleCustomRangeApply = useCallback((start: string, end: string) => {
    setSelectedDate("")
    setCustomRangeStart(start)
    setCustomRangeEnd(end)
    setTimeframe("custom")
  }, [])

  const accounts = useMemo(
    () => buildAccountFilterOptionsFromRows(accountRows),
    [accountRows]
  )

  const copyGroupAccountIds = useMemo(
    () => resolveCopyGroupAccountIdsForFilter(accountFilter, copyGroups),
    [accountFilter, copyGroups]
  )

  useEffect(() => {
    if (accountFilter === "all") return
    if (!isValidAccountFilterValue(accountFilter, accounts, copyGroups)) {
      setAccountFilter("all")
    }
  }, [accounts, accountFilter, copyGroups])

  const tradesForPerformanceSharePool = useMemo(
    () =>
      filterTradesForPerformanceSharePool(trades, {
        selectedDate,
        accountFilter,
        accountTypeFilter,
        resultFilter,
        accountById,
        copyGroupAccountIds,
      }),
    [trades, selectedDate, accountFilter, accountTypeFilter, resultFilter, accountById, copyGroupAccountIds]
  )

  const filteredTrades = useMemo(() => {
    return tradesForPerformanceSharePool.filter((trade) => {
      if (timeframe === "all") return true

      const now = new Date()
      const tradeDate = new Date(trade.created_at)

      if (timeframe === "daily") {
        return tradeDate.toDateString() === now.toDateString()
      }

      if (timeframe === "weekly") {
        const weekAgo = new Date()
        weekAgo.setDate(now.getDate() - 7)
        return tradeDate >= weekAgo
      }

      if (timeframe === "monthly") {
        return (
          tradeDate.getMonth() === now.getMonth() &&
          tradeDate.getFullYear() === now.getFullYear()
        )
      }

      if (timeframe === "yearly") {
        return tradeDate.getFullYear() === now.getFullYear()
      }

      if (timeframe === "custom") {
        if (!customRangeStart?.trim() || !customRangeEnd?.trim()) return true
        const start = new Date(customRangeStart + "T00:00:00")
        const end = new Date(customRangeEnd + "T23:59:59.999")
        return tradeDate >= start && tradeDate <= end
      }

      return true
    })
  }, [tradesForPerformanceSharePool, timeframe, customRangeStart, customRangeEnd])

  const visibleTrades = useMemo(() => {
    const filtered = !showPublicOnly
      ? filteredTrades
      : filteredTrades.filter((t) => t.is_public === true)
    // Sort UI is native-only; keep prior list order on web.
    if (!nativeIos) return filtered
    return sortTradesForDisplay(filtered, sortBy)
  }, [filteredTrades, showPublicOnly, sortBy, nativeIos])

  const displayedTrades = useMemo(
    () => visibleTrades.slice(0, visibleCount),
    [visibleTrades, visibleCount]
  )

  const tradeStats = useMemo(() => {
    const totalTrades = visibleTrades.length
    const wins = visibleTrades.filter((t) => t.pnl > 0)
    const winRate = totalTrades ? (wins.length / totalTrades) * 100 : 0
    const totalPnL = visibleTrades.reduce((sum, t) => sum + (t.pnl || 0), 0)
    const avgRR = averageRrFromTrades(visibleTrades)
    return { totalTrades, winRate, totalPnL, avgRR }
  }, [visibleTrades])

  return (
    <>
      <NativeIosPullToRefresh
        onRefresh={async () => {
          await Promise.all([refreshTrades(), refreshAccounts()])
        }}
      >
      <div
        data-tt-native-surface="trades"
        className="w-full text-white px-2 pb-3 pt-0 md:px-4 md:pb-10"
      >
        <PlatformTradesHeader
          accounts={accounts}
          accountFilter={accountFilter}
          onAccountChange={setAccountFilter}
          isPro={isPro}
          copyGroups={copyGroups}
          accountTypeFilter={accountTypeFilter}
          onAccountTypeChange={setAccountTypeFilter}
          timeframe={timeframe}
          onTimeframeChange={handleTimeframeChange}
          customRangeStart={customRangeStart}
          customRangeEnd={customRangeEnd}
          onCustomRangeApply={handleCustomRangeApply}
          selectedDate={selectedDate}
          onSelectedDateChange={setSelectedDate}
          resultFilter={resultFilter}
          onResultFilterChange={setResultFilter}
          showPublicOnly={showPublicOnly}
          onTogglePublicOnly={handleTogglePublicOnly}
          showAdvanced={showAdvanced}
          onToggleAdvanced={handleToggleAdvanced}
          onOpenPerformanceShare={handleOpenPerformanceShare}
          sortBy={sortBy}
          onSortByChange={setSortBy}
        />

        <div className="w-full px-1 md:px-6 md:max-w-[1600px] md:mx-auto">
          <TradesPageMainContent
            loading={loading}
            accounts={accounts}
            accountFilter={accountFilter}
            onAccountChange={setAccountFilter}
            isPro={isPro}
            copyGroups={copyGroups}
            accountTypeFilter={accountTypeFilter}
            onAccountTypeChange={setAccountTypeFilter}
            timeframe={timeframe}
            onTimeframeChange={handleTimeframeChange}
            customRangeStart={customRangeStart}
            customRangeEnd={customRangeEnd}
            onCustomRangeApply={handleCustomRangeApply}
            selectedDate={selectedDate}
            onSelectedDateChange={setSelectedDate}
            resultFilter={resultFilter}
            onResultFilterChange={setResultFilter}
            onOpenQuickInput={handleOpenQuickInput}
            showAdvanced={showAdvanced}
            onToggleAdvanced={handleToggleAdvanced}
            showPublicOnly={showPublicOnly}
            onTogglePublicOnly={handleTogglePublicOnly}
            onOpenPerformanceShare={handleOpenPerformanceShare}
            tradeStats={tradeStats}
            displayedTrades={displayedTrades}
            visibleTradesLength={visibleTrades.length}
            hasAnyTrades={trades.length > 0}
            visibleCount={visibleCount}
            accountById={accountById}
            gateProfile={gateProfile}
            onEditTrade={handleEditTrade}
            onDeleteTrade={handleDeleteTrade}
            onSendTrade={handleSendTrade}
            onAnalyzeTrade={handleAnalyzeTrade}
            onImageClick={handleImageClick}
            onLoadMore={handleLoadMore}
            tradeReelsByTradeId={tradeReelsByTradeId}
            onOpenTradeReplay={handleOpenTradeReplay}
          />
        </div>
      </div>
      </NativeIosPullToRefresh>

      <TradesPageOverlays
        selectedImage={selectedImage}
        editingTrade={editingTrade}
        showPerformanceShare={showPerformanceShare}
        sendTradeId={sendTradeId}
        tradesForPerformanceSharePool={tradesForPerformanceSharePool}
        gateProfile={gateProfile}
        customRangeStart={customRangeStart}
        customRangeEnd={customRangeEnd}
        onCloseImageLightbox={handleCloseImageLightbox}
        onCloseEditForm={handleCloseEditForm}
        onTradeFormSaved={handleTradeFormSaved}
        onClosePerformanceShare={handleClosePerformanceShare}
        onCloseSendModal={handleCloseSendModal}
      />

      <ConfirmModal {...confirmModalProps} />
      <ProUpgradeModal
        open={showExportUpgradeModal}
        onClose={() => setShowExportUpgradeModal(false)}
        variant="custom"
      />
      <QuickTradeModal
        open={showQuickTrade}
        userId={user?.id ?? null}
        onClose={() => setShowQuickTrade(false)}
      />

      <ReelViewer
        reel={selectedReplay}
        creator={
          gateProfile
            ? {
                username: gateProfile.username,
                avatar_url: gateProfile.avatar_url,
                name: gateProfile.name,
              }
            : null
        }
        onClose={() => setSelectedReplay(null)}
      />
    </>
  )
}
