"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import { useRouter } from "next/navigation"
import InputTradeForm from "../components/InputTradeForm"
import { formatEST } from "@/lib/formatEST"
import { useToast } from "@/app/components/ui"
import { TRADES_APP_SELECT } from "@/lib/publicAccountPrivacy"
import { mapProjectedRows } from "@/lib/supabaseProjectedQuery"
import { useUserProfile } from "@/lib/useUserProfile"

const TRADES_PER_PAGE = 50

type ReviewTrade = {
  id: string | number
  ticker?: string | null
  direction?: string | null
  pnl?: string | number | null
  created_at: string
  [key: string]: unknown
}

export default function ReviewPage() {
  const toast = useToast()
  const { user, loading: profileLoading } = useUserProfile()
  const [trades, setTrades] = useState<ReviewTrade[]>([])
  const [editingTrade, setEditingTrade] = useState<ReviewTrade | null>(null)
  const [showApproveAllConfirm, setShowApproveAllConfirm] = useState(false)
  const [bulkApproving, setBulkApproving] = useState(false)
  const [loading, setLoading] = useState(true)
  const [currentPage, setCurrentPage] = useState(1)

  const router = useRouter()

  const pageCount = Math.max(1, Math.ceil(trades.length / TRADES_PER_PAGE))
  const visibleTrades = useMemo(() => {
    const start = (currentPage - 1) * TRADES_PER_PAGE
    return trades.slice(start, start + TRADES_PER_PAGE)
  }, [currentPage, trades])

  const fetchTrades = useCallback(async () => {
    const { data } = await supabase
      .from("trades")
      .select(TRADES_APP_SELECT)
      .eq("user_id", user?.id)
      .eq("is_initial_import", true)
      .eq("reviewed", false)
      .order("created_at", { ascending: true })
      .overrideTypes<Record<string, unknown>[], { merge: false }>()

    const nextTrades = mapProjectedRows(
      data,
      (row) => row as ReviewTrade
    )
    const nextPageCount = Math.max(
      1,
      Math.ceil(nextTrades.length / TRADES_PER_PAGE)
    )
    setTrades(nextTrades)
    setCurrentPage((page) => Math.min(page, nextPageCount))
    setLoading(false)
  }, [user?.id])

  useEffect(() => {
    if (profileLoading) return
    // The state updates happen after the Supabase request resolves.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void fetchTrades()
  }, [fetchTrades, profileLoading])

  async function handleApproveAll() {
    if (!user?.id) return

    setBulkApproving(true)
    const { error } = await supabase
      .from("trades")
      .update({ reviewed: true })
      .eq("user_id", user.id)
      .eq("is_initial_import", true)
      .eq("reviewed", false)

    if (error) {
      console.error("Approve all failed:", error)
      toast.error("Failed to approve all imported trades.")
    } else {
      setShowApproveAllConfirm(false)
      await fetchTrades()
      toast.success("All pending imported trades were approved.")
    }
    setBulkApproving(false)
  }

  if (loading) {
    return (
      <>
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-10">
          Loading trades...
        </div>
      </>
    )
  }

  if (!trades.length) {
    return (
      <>
        <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">
          <div className="text-center">
            <h1 className="text-2xl font-bold text-blue-300">No trades left to review 🎉</h1>
            <button
              type="button"
              onClick={() => router.push("/app")}
              className="mt-4 rounded bg-blue-500 px-4 py-2 font-semibold hover:bg-blue-600 disabled:hover:bg-blue-500"
            >
              Back to Add Trade
            </button>
          </div>
        </div>
      </>
    )
  }

  return (
    <>

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">
        <div className="max-w-6xl mx-auto p-4 md:p-8">
          <div className="mb-6 md:flex md:items-center md:justify-between md:gap-3">
            <div className="md:hidden">
              <h1 className="text-2xl font-bold leading-tight text-blue-300">
                Review CSV Import
              </h1>
              <p className="mt-1 text-sm font-medium text-gray-300">
                {trades.length} Pending
              </p>
              <div className="mt-4 grid grid-cols-2 gap-3">
                <button
                  type="button"
                  onClick={() => router.push("/app")}
                  className="h-10 min-w-0 rounded-lg bg-white/10 px-3 text-sm font-medium hover:bg-white/20"
                >
                  Back
                </button>
                <button
                  type="button"
                  onClick={() => setShowApproveAllConfirm(true)}
                  disabled={!trades.length}
                  className="h-10 min-w-0 rounded-lg bg-blue-500 px-3 text-sm font-semibold hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:bg-blue-500"
                >
                  Approve All
                </button>
              </div>
            </div>

            <h1 className="hidden text-2xl font-bold text-blue-300 md:block">
              Review CSV Inputs ({trades.length} pending)
            </h1>
            <div className="hidden items-center gap-2 md:flex">
              <button
                type="button"
                onClick={() => setShowApproveAllConfirm(true)}
                disabled={!trades.length}
                className="rounded bg-blue-500 px-3 py-2 text-sm font-semibold hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:bg-blue-500"
              >
                Approve All
              </button>
              <button
                type="button"
                onClick={() => router.push("/app")}
                className="rounded bg-white/10 px-3 py-2 text-sm hover:bg-white/20"
              >
                Back
              </button>
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {visibleTrades.map((trade, i) => (
              <button
                key={trade.id}
                type="button"
                onClick={() => setEditingTrade(trade)}
                className="rounded-xl border border-white/10 bg-white/5 p-4 text-left transition hover:border-white/20 hover:bg-white/10"
              >
                <div className="flex items-center justify-between">
                  <p className="font-semibold">
                    {(currentPage - 1) * TRADES_PER_PAGE + i + 1}.{" "}
                    {trade.ticker || "—"} • {trade.direction || "—"}
                  </p>
                  <span
                    className={`font-semibold ${
                      Number(trade.pnl) >= 0 ? "text-emerald-400" : "text-red-400"
                    }`}
                  >
                    {Number.isFinite(Number(trade.pnl))
                      ? `${Number(trade.pnl) >= 0 ? "$" : "-$"}${Math.abs(
                          Number(trade.pnl)
                        ).toLocaleString(undefined, {
                          minimumFractionDigits: 2,
                          maximumFractionDigits: 2,
                        })}`
                      : "—"}
                  </span>
                </div>
                <p className="mt-1 text-xs text-gray-400">
                  {formatEST(trade.created_at)}
                </p>
                <p className="mt-3 inline-flex rounded bg-emerald-500 px-3 py-1 text-xs font-semibold text-white">
                  Review / Edit Trade
                </p>
              </button>
            ))}
          </div>

          {pageCount > 1 ? (
            <nav
              aria-label="CSV review pages"
              className="mt-6 flex items-center justify-between gap-3"
            >
              <button
                type="button"
                onClick={() => {
                  setCurrentPage((page) => Math.max(1, page - 1))
                  window.scrollTo({ top: 0, behavior: "smooth" })
                }}
                disabled={currentPage === 1}
                className="h-10 rounded-lg bg-white/10 px-4 text-sm font-medium hover:bg-white/20 disabled:cursor-not-allowed disabled:opacity-40"
              >
                Previous
              </button>
              <p className="min-w-0 text-center text-sm text-gray-300">
                Page {currentPage} of {pageCount}
                <span className="hidden sm:inline">
                  {" "}
                  · {visibleTrades.length} of {trades.length} trades
                </span>
              </p>
              <button
                type="button"
                onClick={() => {
                  setCurrentPage((page) => Math.min(pageCount, page + 1))
                  window.scrollTo({ top: 0, behavior: "smooth" })
                }}
                disabled={currentPage === pageCount}
                className="h-10 rounded-lg bg-white/10 px-4 text-sm font-medium hover:bg-white/20 disabled:cursor-not-allowed disabled:opacity-40"
              >
                Next
              </button>
            </nav>
          ) : null}
        </div>
      </div>

      {editingTrade ? (
        <InputTradeForm
          key={String(editingTrade.id)}
          existingTrade={editingTrade}
          forceMarkReviewedOnSave={true}
          onClose={() => setEditingTrade(null)}
          onSave={() => {
            setEditingTrade(null)
            void fetchTrades()
          }}
        />
      ) : null}

      {showApproveAllConfirm ? (
        <div className="fixed inset-0 z-[120] flex items-center justify-center bg-black/70 backdrop-blur-sm p-4">
          <div className="w-full max-w-md rounded-xl border border-white/10 bg-[#0f172a] p-5 text-white shadow-xl">
            <h2 className="text-lg font-semibold">Approve All Imported Trades</h2>
            <p className="mt-3 text-sm text-gray-300">
              Are you sure you want to approve all imported trades?
            </p>
            <p className="mt-1 text-sm text-gray-400">
              This will mark all pending imported trades as reviewed without opening them individually.
            </p>
            <div className="mt-5 flex items-center justify-end gap-2">
              <button
                type="button"
                onClick={() => setShowApproveAllConfirm(false)}
                disabled={bulkApproving}
                className="rounded bg-white/10 px-3 py-2 text-sm hover:bg-white/20 disabled:opacity-60"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={() => void handleApproveAll()}
                disabled={bulkApproving}
                className="rounded bg-blue-500 px-3 py-2 text-sm font-semibold hover:bg-blue-600 disabled:opacity-60 disabled:hover:bg-blue-500"
              >
                {bulkApproving ? "Approving..." : "Approve All"}
              </button>
            </div>
          </div>
        </div>
      ) : null}

    </>
  )
}