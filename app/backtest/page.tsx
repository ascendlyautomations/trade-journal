"use client"

import dynamic from "next/dynamic"
import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "@/lib/supabase"
import { deleteUserTrade } from "@/lib/deleteTrade"
import { isProActive } from "@/lib/subscription"
import LockedFeature from "../components/LockedFeature"
import TradesPageTradeCard from "../components/TradesPageTradeCard"
import Calendar from "@/components/Calendar"
import { formatPnlCurrency } from "@/lib/formatMoney"
import { formatRR } from "@/lib/formatDisplay"
import { averageRrFromTrades } from "@/lib/tradeRr"
import { ConfirmModal, useDeleteTradeConfirmation } from "../components/ui"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { isDemoSupabaseBlocked } from "@/lib/demo/demoSupabaseGuard"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import { tradeAnalysisHref } from "@/lib/tradeAnalysisNavigation"
import { getDemoBacktestTrades } from "@/lib/demo/demoBacktest"
import { DEMO_PROFILE } from "@/lib/demo/fixtures"
import { TRADES_APP_SELECT } from "@/lib/publicAccountPrivacy"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { SkeletonBacktestPageContent } from "../components/ui/skeletons"
import ImageLightbox from "../components/ui/ImageLightbox"

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

export default function BacktestPage() {
  const router = useRouter()
  const { user, profile: contextProfile } = useUserProfile()
  const [trades, setTrades] = useState<BacktestTrade[]>([])
  const [loading, setLoading] = useState(true)
  const [selectedStrategy, setSelectedStrategy] = useState("all")
  const [showAdvanced, setShowAdvanced] = useState(false)
  const [editingTrade, setEditingTrade] = useState<BacktestTrade | null>(null)
  const [selectedImage, setSelectedImage] = useState<string | null>(null)
  const [showPerformanceShare, setShowPerformanceShare] = useState(false)
  const [proLocked, setProLocked] = useState(false)
  const [shareProfile, setShareProfile] = useState<{
    referral_code?: string | null
  } | null>(null)

  useEffect(() => {
    if (isDemoModeActive() && !user?.id) return
    void loadBacktests()
  }, [user?.id])

  const loadBacktests = async () => {
    if (isDemoModeActive() && user?.id) {
      setShareProfile({ referral_code: DEMO_PROFILE.referral_code })
      setTrades(getDemoBacktestTrades() as BacktestTrade[])
      setProLocked(false)
      setLoading(false)
      return
    }

    if (!user?.id) {
      router.push("/login")
      setLoading(false)
      return
    }

    if (contextProfile && isProActive(contextProfile)) {
      setShareProfile(
        contextProfile.referral_code != null
          ? { referral_code: contextProfile.referral_code }
          : null
      )
    } else {
      const { data: profileRow } = await supabase
        .from("profiles")
        .select("is_pro, subscription_status, referral_code")
        .eq("id", user.id)
        .maybeSingle()
      if (!isProActive(profileRow)) {
        setProLocked(true)
        setLoading(false)
        return
      }
      setShareProfile(profileRow ?? null)
    }

    const { data, error } = await supabase
      .from("trades")
      .select(TRADES_APP_SELECT)
      .eq("user_id", user.id)
      .eq("mode", "backtest")
      .order("created_at", { ascending: false })

    if (!error) setTrades((data as BacktestTrade[]) || [])
    setLoading(false)
  }

  const strategies = useMemo(
    () => [
      "all",
      ...Array.from(
        new Set(
          trades
            .map((t) => t.strategy)
            .filter((s): s is string => Boolean(s && String(s).trim()))
        )
      ),
    ],
    [trades]
  )

  const filteredTrades = useMemo(() => {
    if (selectedStrategy === "all") return trades
    return trades.filter((t) => t.strategy === selectedStrategy)
  }, [trades, selectedStrategy])

  const totalTrades = filteredTrades.length
  const wins = filteredTrades.filter((t) => (Number(t.pnl) || 0) > 0).length
  const losses = filteredTrades.filter((t) => (Number(t.pnl) || 0) < 0).length

  const winRate = totalTrades
    ? ((wins / totalTrades) * 100).toFixed(1)
    : "0"

  const totalPnL = filteredTrades.reduce(
    (acc, t) => acc + (Number(t.pnl) || 0),
    0
  )

  const avgRR = averageRrFromTrades(filteredTrades)

  const strategyMap: Record<string, BacktestTrade[]> = {}
  trades.forEach((t) => {
    if (!t.strategy) return
    const name = String(t.strategy)
    if (!strategyMap[name]) strategyMap[name] = []
    strategyMap[name].push(t)
  })

  const performDeleteTrade = useCallback(async (id: string) => {
    if (isDemoSupabaseBlocked()) {
      requestDemoSignup("delete")
      return
    }
    await deleteUserTrade(supabase, id)
    setTrades((prev) => prev.filter((t) => t.id !== id))
  }, [])

  const handleEditTrade = useCallback((trade: BacktestTrade) => {
    if (isDemoSupabaseBlocked()) {
      requestDemoSignup("edit")
      return
    }
    setEditingTrade(trade)
  }, [])

  const handleSendTrade = useCallback((_trade: BacktestTrade) => {
    if (isDemoSupabaseBlocked()) {
      requestDemoSignup("trade")
    }
  }, [])

  const handleAnalyzeTrade = useCallback(
    (trade: BacktestTrade) => {
      if (isDemoModeActive()) {
        requestDemoSignup("ai")
        return
      }
      router.push(tradeAnalysisHref(trade.id))
    },
    [router]
  )

  const { requestDelete: deleteTrade, confirmModalProps } =
    useDeleteTradeConfirmation(performDeleteTrade)

  if (proLocked) {
    return (
      <>
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100">
          <div className="mx-auto max-w-7xl px-6 pb-6 pt-6">
            <LockedFeature title="Backtest Lab" className="mx-auto max-w-lg" />
          </div>
        </div>
      </>
    )
  }

  return (
    <>
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100">
        <div className="mx-auto max-w-7xl px-6 pb-6 pt-3">
          <h1 className="text-xl md:text-2xl font-semibold text-blue-300 text-center mb-1 mt-0 md:mt-0">
  Backtest Lab
</h1>
          <p className="mb-2 text-center text-sm text-gray-400">
            Isolated backtests, does not affect dashboard or trade history.
          </p>

          <div className="mb-3 flex flex-wrap items-center justify-between gap-4">
            <div className="flex items-center gap-4">
              <select
                value={selectedStrategy}
                onChange={(e) => setSelectedStrategy(e.target.value)}
                className="rounded-lg border border-white/10 bg-black/40 px-4 py-2 text-white"
              >
                {strategies.map((s) => (
                  <option key={s} value={s}>
                    {s === "all" ? "All Strategies" : s}
                  </option>
                ))}
              </select>
            </div>
            <div className="flex flex-wrap items-center gap-2">
              <button
                type="button"
                onClick={() => setShowPerformanceShare(true)}
                className="rounded-lg bg-white/10 px-4 py-2 text-sm text-white hover:bg-white/20"
                title="Share performance"
                aria-label="Share performance"
              >
                📤 Share
              </button>
              <button
                type="button"
                onClick={() => setShowAdvanced((v) => !v)}
                className="rounded-lg bg-white/10 px-4 py-2 text-sm text-white hover:bg-white/20"
              >
                {showAdvanced ? "Hide Advanced" : "Show Advanced"}
              </button>
            </div>
          </div>

          {loading ? (
            <SkeletonBacktestPageContent />
          ) : (
            <>
          <div className="mb-4 grid grid-cols-2 gap-4 md:grid-cols-4">
            <div className="rounded-xl bg-gradient-to-br from-blue-500/20 to-blue-600/10 p-4">
              <p className="text-sm text-gray-400">Trades</p>
              <p className="text-xl font-bold text-white">{totalTrades}</p>
            </div>

            <div className="rounded-xl bg-gradient-to-br from-green-500/20 to-green-600/10 p-4">
              <p className="text-sm text-gray-400">Win Rate</p>
              <p className="text-xl font-bold text-white">{winRate}%</p>
            </div>

            <div className="rounded-xl bg-gradient-to-br from-purple-500/20 to-purple-600/10 p-4">
              <p className="text-sm text-gray-400">Total PnL</p>
              <p className="text-xl font-bold text-white">
                {formatPnlCurrency(totalPnL, {
                  minimumFractionDigits: 0,
                  maximumFractionDigits: 2,
                })}
              </p>
            </div>

            <div className="rounded-xl bg-gradient-to-br from-yellow-500/20 to-yellow-600/10 p-4">
              <p className="text-sm text-gray-400">Avg RR</p>
              <p className="text-xl font-bold text-white">{formatRR(avgRR)}</p>
            </div>
          </div>

          <div className="mb-5 rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-sm text-gray-300">
            Wins: <span className="font-semibold text-emerald-400">{wins}</span>{" "}
            / Losses:{" "}
            <span className="font-semibold text-red-400">{losses}</span>
          </div>

          <h2 className="mb-2 text-xl font-semibold text-white">
            Backtest Calendar
          </h2>
          <div className="mb-4">
            <Calendar trades={filteredTrades as any} />
          </div>

          <h2 className="mb-3 text-xl font-semibold text-white">
            Strategy Breakdown
          </h2>
          <div className="mb-4 space-y-4">
            {Object.entries(strategyMap)
              .filter(([name]) =>
                selectedStrategy === "all" ? true : name === selectedStrategy
              )
              .map(([name, stratTrades]) => {
              const stratWins = stratTrades.filter(
                (t) => (Number(t.pnl) || 0) > 0
              ).length
              const total = stratTrades.length
              const pnl = stratTrades.reduce(
                (acc, t) => acc + (Number(t.pnl) || 0),
                0
              )
              const stratAvgRR = averageRrFromTrades(stratTrades)
              return (
                <div
                  key={name}
                  className="rounded-xl border border-white/10 bg-white/5 p-4 backdrop-blur-md"
                >
                  <p className="font-bold text-white">{name}</p>
                  <p className="text-sm text-gray-300">Trades: {total}</p>
                  <p className="text-sm text-gray-300">
                    Win Rate: {((stratWins / total) * 100).toFixed(1)}%
                  </p>
                  <p className="text-sm text-gray-300">
                    PnL:{" "}
                    {formatPnlCurrency(pnl, {
                      minimumFractionDigits: 0,
                      maximumFractionDigits: 2,
                    })}
                  </p>
                  <p className="text-xs text-gray-400">
                    Avg RR: {formatRR(stratAvgRR)}
                  </p>
                </div>
              )
            })}
            {Object.keys(strategyMap).length === 0 ? (
              <p className="text-sm text-gray-400">
                No strategy labels yet — add a strategy name on backtest trades.
              </p>
            ) : null}
          </div>

          <h2 className="mb-3 text-xl font-semibold text-white">
            Backtest Trades
          </h2>
          <div className="grid grid-cols-1 gap-4 pb-12 md:grid-cols-2">
            {filteredTrades.map((trade) => (
              <TradesPageTradeCard
                key={trade.id}
                trade={trade}
                showAdvanced={showAdvanced}
                shareProfile={shareProfile}
                onEdit={handleEditTrade}
                onDelete={(id) => void deleteTrade(id)}
                onSendClick={handleSendTrade}
                onAnalyze={handleAnalyzeTrade}
                onImageClick={(url) => setSelectedImage(url)}
              />
            ))}
            {!loading && filteredTrades.length === 0 ? (
              <p className="text-center text-gray-400 md:col-span-2">
                No backtest trades match this filter.
              </p>
            ) : null}
          </div>
            </>
          )}
        </div>
      </div>

      <ImageLightbox
        imageUrl={selectedImage}
        onClose={() => setSelectedImage(null)}
      />

      {editingTrade ? (
        <InputTradeForm
          existingTrade={editingTrade}
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
        subtitle="Backtest Lab · current strategy filter"
        profile={shareProfile}
      />
      <ConfirmModal {...confirmModalProps} />
    </>
  )
}
