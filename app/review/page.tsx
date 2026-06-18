"use client"

import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import Navbar from "../components/Navbar"
import { useRouter } from "next/navigation"
import InputTradeForm from "../components/InputTradeForm"
import { formatEST } from "@/lib/formatEST"
import { useToast } from "@/app/components/ui"

export default function ReviewPage() {
  const toast = useToast()
  const [trades, setTrades] = useState<any[]>([])
  const [editingTrade, setEditingTrade] = useState<any | null>(null)
  const [showApproveAllConfirm, setShowApproveAllConfirm] = useState(false)
  const [bulkApproving, setBulkApproving] = useState(false)
  const [loading, setLoading] = useState(true)

  const router = useRouter()

  useEffect(() => {
    fetchTrades()
  }, [])

  async function fetchTrades() {
    const {
      data: { user }
    } = await supabase.auth.getUser()

    const { data } = await supabase
      .from("trades")
      .select("*")
      .eq("user_id", user?.id)
      .eq("is_initial_import", true)
      .eq("reviewed", false)
      .order("created_at", { ascending: true })

    setTrades(data || [])
    setLoading(false)
  }

  async function handleApproveAll() {
    const {
      data: { user },
    } = await supabase.auth.getUser()
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
        <Navbar />
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-10">
          Loading trades...
        </div>
      </>
    )
  }

  if (!trades.length) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">
          <div className="text-center">
            <h1 className="text-2xl font-bold">No trades left to review 🎉</h1>
            <button
              type="button"
              onClick={() => router.push("/app")}
              className="mt-4 rounded bg-emerald-500 px-4 py-2 font-semibold hover:bg-emerald-600"
            >
              Back to Input Trade
            </button>
          </div>
        </div>
      </>
    )
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">
        <div className="max-w-6xl mx-auto p-4 md:p-8">
          <div className="mb-6 flex items-center justify-between gap-3">
            <h1 className="text-2xl bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent font-bold">
              Review CSV Inputs ({trades.length} pending)
            </h1>
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => setShowApproveAllConfirm(true)}
                disabled={!trades.length}
                className="rounded bg-emerald-600 px-3 py-2 text-sm font-semibold hover:bg-emerald-500 disabled:opacity-50 disabled:cursor-not-allowed"
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
            {trades.map((trade, i) => (
              <button
                key={trade.id}
                type="button"
                onClick={() => setEditingTrade(trade)}
                className="rounded-xl border border-white/10 bg-white/5 p-4 text-left transition hover:border-white/20 hover:bg-white/10"
              >
                <div className="flex items-center justify-between">
                  <p className="font-semibold">
                    {i + 1}. {trade.ticker || "—"} • {trade.direction || "—"}
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
        </div>
      </div>

      {editingTrade ? (
        <InputTradeForm
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
                className="rounded bg-emerald-600 px-3 py-2 text-sm font-semibold hover:bg-emerald-500 disabled:opacity-60"
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