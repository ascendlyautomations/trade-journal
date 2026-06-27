"use client"

import { filterTradesForPerformanceSharePool } from "@/lib/performanceShare"
import { excludeBacktestTrades } from "@/lib/tradeModeFilters"
import { averageRrFromTrades } from "@/lib/tradeRr"
import { useCallback, useEffect, useMemo, useState } from "react"
import { supabase } from "../../../lib/supabaseClient"
import { deleteUserTrade } from "@/lib/deleteTrade"
import {
  buildTradeAccountFilterKey,
  formatAccountNameWithSizeDisplay,
  resolveTradeAccountName,
  resolveTradeAccountSize,
} from "@/lib/tradeAccountDisplay"
import { useRouter } from "next/navigation"
import TradesPageMainContent from "../../components/TradesPageMainContent"
import TradesPageOverlays from "../../components/TradesPageOverlays"
import { ConfirmModal, useDeleteTradeConfirmation } from "../../components/ui"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { useCachedAccounts, useCachedTrades } from "@/lib/useAppDataCache"
import { getCachedAccounts, getCachedTrades } from "@/lib/appDataCache"

export default function TradesPage() {
  const { user, profile: gateProfile, loading: profileLoading } = useUserProfile()
  const { trades: cachedTrades, loading: tradesLoading } = useCachedTrades(user?.id)
  const { accounts: accountRows, loading: accountsLoading } = useCachedAccounts(
    user?.id
  )
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
  const [sendTradeId, setSendTradeId] = useState<string | null>(null)
  const [visibleCount, setVisibleCount] = useState(10)
  const router = useRouter()

  const accountById = useMemo(() => {
    const m: Record<string, any> = {}
    accountRows.forEach((acc) => {
      m[String(acc.id)] = acc
    })
    return m
  }, [accountRows])

  useEffect(() => {
    if (!profileLoading && !user) {
      router.push("/login")
    }
  }, [profileLoading, user, router])

  useEffect(() => {
    setVisibleCount(10)
  }, [timeframe, accountFilter, accountTypeFilter, resultFilter])

  useEffect(() => {
    if (typeof window === "undefined" || loading || trades.length === 0) return

    const editId = new URLSearchParams(window.location.search).get("edit")?.trim()
    if (!editId) return

    const trade = trades.find((t) => String(t.id) === editId)
    if (trade) {
      setEditingTrade({ ...trade })
    }
  }, [loading, trades])

  const handleEditTrade = useCallback((trade: any) => {
    setEditingTrade({ ...trade })
  }, [])

  const performDeleteTrade = useCallback(
    async (id: string) => {
      await deleteUserTrade(supabase, id, { userId: user?.id })
    },
    [user?.id]
  )

  const { requestDelete: handleDeleteTrade, confirmModalProps } =
    useDeleteTradeConfirmation(performDeleteTrade)

  const handleSendTrade = useCallback((trade: any) => {
    setSendTradeId(String(trade.id))
  }, [])

  const handleAnalyzeTrade = useCallback(
    (trade: any) => {
      router.push(`/analyst?trade=${encodeURIComponent(String(trade.id))}`)
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
    setShowPerformanceShare(true)
  }, [])

  const handleToggleAdvanced = useCallback(() => {
    setShowAdvanced((prev) => !prev)
  }, [])

  const handleTogglePublicOnly = useCallback(() => {
    setShowPublicOnly((prev) => !prev)
  }, [])

  const handleLoadMore = useCallback(() => {
    setVisibleCount((prev) => prev + 10)
  }, [])

  const handleTradeFormSaved = useCallback(() => {
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

  const accounts = useMemo(() => {
    const accountFilterMap = new Map<
      string,
      { value: string; label: string; accountType?: string | null }
    >()
    trades
      .filter((t) => t.account_id)
      .forEach((t) => {
        const id = String(t.account_id || "").trim()
        const accRow = accountById[id]
        if (accRow?.is_active === false) return
        const accountName = resolveTradeAccountName(t, accRow)
        const size = resolveTradeAccountSize(t, accRow)
        if (!accountName || !size || !id) return
        const value = buildTradeAccountFilterKey(t, accRow)
        const num = accRow?.account_number
        const label = [
          formatAccountNameWithSizeDisplay(accountName, size),
          num ? `• #${num}` : "",
        ]
          .filter((x) => x !== "")
          .join(" ")
          .replace(/\s+/g, " ")
          .trim()
        if (!accountFilterMap.has(value)) {
          accountFilterMap.set(value, {
            value,
            label,
            accountType: t.mode ?? t.account_type,
          })
        }
      })
    return Array.from(accountFilterMap.values())
  }, [trades, accountById])

  useEffect(() => {
    if (accountFilter === "all") return
    if (!accounts.some((a) => a.value === accountFilter)) {
      setAccountFilter("all")
    }
  }, [accounts, accountFilter])

  const tradesForPerformanceSharePool = useMemo(
    () =>
      filterTradesForPerformanceSharePool(trades, {
        selectedDate,
        accountFilter,
        accountTypeFilter,
        resultFilter,
        accountById,
      }),
    [trades, selectedDate, accountFilter, accountTypeFilter, resultFilter]
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
    if (!showPublicOnly) return filteredTrades
    return filteredTrades.filter((t) => t.is_public === true)
  }, [filteredTrades, showPublicOnly])

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
      <div className="w-full text-white px-2 pb-3 pt-0 md:px-4 md:pb-10">

        <div className="relative z-50 w-full px-1 md:px-6 md:max-w-[1600px] md:mx-auto">
          <TradesPageMainContent
            loading={loading}
            accounts={accounts}
            accountFilter={accountFilter}
            onAccountChange={setAccountFilter}
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
            showAdvanced={showAdvanced}
            onToggleAdvanced={handleToggleAdvanced}
            showPublicOnly={showPublicOnly}
            onTogglePublicOnly={handleTogglePublicOnly}
            onOpenPerformanceShare={handleOpenPerformanceShare}
            tradeStats={tradeStats}
            displayedTrades={displayedTrades}
            visibleTradesLength={visibleTrades.length}
            visibleCount={visibleCount}
            accountById={accountById}
            gateProfile={gateProfile}
            onEditTrade={handleEditTrade}
            onDeleteTrade={handleDeleteTrade}
            onSendClick={handleSendTrade}
            onAnalyze={handleAnalyzeTrade}
            onImageClick={handleImageClick}
            onLoadMore={handleLoadMore}
          />
        </div>
      </div>

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
    </>
  )
}
