"use client"

import ProfileOnboarding, {
  ONBOARDING_FLAG,
  profileNeedsUsername,
} from "../../components/ProfileOnboarding"
import { filterTradesForPerformanceSharePool } from "@/lib/performanceShare"
import { useCallback, useEffect, useMemo, useState } from "react"
import { supabase } from "../../../lib/supabaseClient"
import { useRouter } from "next/navigation"
import { profilePath } from "@/lib/profileRoutes"
import { normalizeProfileUsername } from "@/lib/profileUsername"
import PostSetupImportModal from "../../components/PostSetupImportModal"
import TradesPageMainContent from "../../components/TradesPageMainContent"
import TradesPageOverlays from "../../components/TradesPageOverlays"
import { ConfirmModal, useDeleteTradeConfirmation } from "../../components/ui"

const TRADES_GATE_PROFILE_SELECT =
  "username, bio, trading_style, trader_type, primary_market, started_trading, avatar_url, referral_code" as const

export default function TradesPage() {
  const [trades, setTrades] = useState<any[]>([])
  const [resultFilter, setResultFilter] = useState<"all" | "wins" | "losses">("all")
  const [selectedImage, setSelectedImage] = useState<string | null>(null)
  const [accountFilter, setAccountFilter] = useState("all")
  const [accountTypeFilter, setAccountTypeFilter] = useState("all")
  const [showPublicOnly, setShowPublicOnly] = useState(false)
  const [showAdvanced, setShowAdvanced] = useState(false)
  const [timeframe, setTimeframe] = useState("all")
  const [customRangeStart, setCustomRangeStart] = useState("")
  const [customRangeEnd, setCustomRangeEnd] = useState("")
  const [loading, setLoading] = useState(true)
  const [selectedDate, setSelectedDate] = useState("")
  const [editingTrade, setEditingTrade] = useState<any | null>(null)
  const [authUserId, setAuthUserId] = useState<string | null>(null)
  const [gateProfile, setGateProfile] = useState<any | null>(null)
  const [showOnboarding, setShowOnboarding] = useState(false)
  const [showImportModal, setShowImportModal] = useState(false)
  const [showPerformanceShare, setShowPerformanceShare] = useState(false)
  const [sendTradeId, setSendTradeId] = useState<string | null>(null)
  const [visibleCount, setVisibleCount] = useState(10)
  /** Account rows for id → account_number (trades query unchanged; separate fetch) */
  const [accountRows, setAccountRows] = useState<any[]>([])
  const router = useRouter()

  const accountById = useMemo(() => {
    const m: Record<string, any> = {}
    accountRows.forEach((acc) => {
      m[String(acc.id)] = acc
    })
    return m
  }, [accountRows])

  useEffect(() => {
    initPage()
  }, [])

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

  useEffect(() => {
    if (loading || !gateProfile) return
    let fromSignup = false
    try {
      fromSignup = sessionStorage.getItem(ONBOARDING_FLAG) === "1"
    } catch {
      /* ignore */
    }
    if (fromSignup || profileNeedsUsername(gateProfile.username)) {
      setShowOnboarding(true)
    }
  }, [loading, gateProfile])

  async function initPage() {
    const {
      data: { user }
    } = await supabase.auth.getUser()

    if (!user) {
      router.push("/login")
      return
    }

    setAuthUserId(user.id)

    // 🔥 CREATE PROFILE IF NEEDED (GOOGLE FIX)
    const { data: existingProfile } = await supabase
      .from("profiles")
      .select("id")
      .eq("id", user.id)

    if (!existingProfile || existingProfile.length === 0) {
      const referralCode =
        typeof window !== "undefined"
          ? localStorage.getItem("referral_code")
          : null

      console.log("🔥 REFERRAL ON SIGNUP:", referralCode)

      function generateReferralCode() {
        return Math.random().toString(36).substring(2, 8).toUpperCase()
      }

      const rawUsername =
        user.user_metadata?.email?.split("@")[0] ||
        user.email ||
        `user_${user.id.slice(0, 6)}`
      const { error: profileUpsertErr } = await supabase
        .from("profiles")
        .upsert(
          {
            id: user.id,
            username:
              normalizeProfileUsername(rawUsername) ||
              `user_${user.id.slice(0, 6)}`,
            name: user.user_metadata?.full_name || "",
            is_pro: false,
            subscription_status: "inactive",
            created_at: new Date().toISOString(),
            referral_code: generateReferralCode(),
            referred_by: referralCode || null,
          },
          { onConflict: "id", ignoreDuplicates: true }
        )

      if (profileUpsertErr) {
        console.error(
          "ERROR:",
          JSON.stringify(profileUpsertErr, null, 2)
        )
      }
    }

    const { data: profRow } = await supabase
      .from("profiles")
      .select(TRADES_GATE_PROFILE_SELECT)
      .eq("id", user.id)
      .maybeSingle()

    setGateProfile(profRow ?? null)

    const { data: accountsData } = await supabase
      .from("accounts")
      .select("id, account_number, name, account_size, mode, category, is_active")
      .eq("user_id", user.id)
    setAccountRows(accountsData || [])

    await fetchTrades(user.id)
  }

  const fetchTrades = useCallback(async (userId: string) => {
    const { data: tradesData } = await supabase
      .from("trades")
      .select("*")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })

    console.log("FETCHED TRADES:", tradesData)

    setTrades(tradesData || [])
    setLoading(false)
  }, [])

  const handleEditTrade = useCallback((trade: any) => {
    setEditingTrade({ ...trade })
  }, [])

  const performDeleteTrade = useCallback(async (id: string) => {
    await supabase.from("trades").delete().eq("id", id)
    setTrades((prev) => prev.filter((t) => t.id !== id))
  }, [])

  const { requestDelete: handleDeleteTrade, confirmModalProps } =
    useDeleteTradeConfirmation(performDeleteTrade)

  const handleSendTrade = useCallback((trade: any) => {
    setSendTradeId(String(trade.id))
  }, [])

  const handleImageClick = useCallback((url: string) => {
    setSelectedImage(url)
  }, [])

  const handleCloseImageLightbox = useCallback(() => {
    setSelectedImage(null)
  }, [])

  const handleCloseEditForm = useCallback(() => {
    setEditingTrade(null)
  }, [])

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

  const handleTradeFormSaved = useCallback(async () => {
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (user) await fetchTrades(user.id)
  }, [fetchTrades])

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
      .filter((t) => t.account_name && t.account_size && t.account_id)
      .forEach((t) => {
        const accountName = String(t.account_name || "").trim()
        const size = String(t.account_size || "").trim()
        const id = String(t.account_id || "").trim()
        const accRow = accountById[id]
        if (accRow?.is_active === false) return
        const value = `${accountName}|${size}|${id}`
        const num = accRow?.account_number
        const label = [accountName, size, num ? `• #${num}` : ""]
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
    const avgRR =
      visibleTrades.reduce((sum, t) => sum + (Number(t.rr) || 0), 0) /
      (totalTrades || 1)
    return { totalTrades, winRate, totalPnL, avgRR }
  }, [visibleTrades])

  return (
    <>
      {showOnboarding && authUserId && gateProfile ? (
        <ProfileOnboarding
          userId={authUserId}
          initialUsername={gateProfile.username}
          initialBio={gateProfile.bio}
          initialTradingStyle={gateProfile.trading_style}
          initialTraderType={gateProfile.trader_type}
          initialPrimaryMarket={gateProfile.primary_market}
          initialStartedTrading={gateProfile.started_trading}
          initialAvatarUrl={gateProfile.avatar_url}
          suppressPostSaveRedirect
          onComplete={(patch) => {
            setGateProfile((p: any) => (p ? { ...p, ...patch } : p))
            setShowOnboarding(false)
            setShowImportModal(true)
          }}
        />
      ) : null}

      <PostSetupImportModal
        open={showImportModal}
        onComplete={async () => {
          setShowImportModal(false)
          if (authUserId) {
            router.push(
              profilePath({
                id: authUserId,
                username: gateProfile?.username,
              })
            )
            router.refresh()
          }
        }}
      />

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
            onSendTrade={handleSendTrade}
            onImageClick={handleImageClick}
            onLoadMore={handleLoadMore}
            onImportCsv={() => setShowImportModal(true)}
          />
        </div>
      </div>

      {selectedImage || editingTrade || showPerformanceShare || sendTradeId ? (
        <TradesPageOverlays
          selectedImage={selectedImage}
          editingTrade={editingTrade}
          showPerformanceShare={showPerformanceShare}
          sendTradeId={sendTradeId}
          tradesForPerformanceSharePool={tradesForPerformanceSharePool}
          gateProfile={gateProfile}
          onCloseImageLightbox={handleCloseImageLightbox}
          onCloseEditForm={handleCloseEditForm}
          onTradeFormSaved={() => void handleTradeFormSaved()}
          onClosePerformanceShare={handleClosePerformanceShare}
          onCloseSendModal={handleCloseSendModal}
        />
      ) : null}

      <ConfirmModal {...confirmModalProps} />
    </>
  )
}
