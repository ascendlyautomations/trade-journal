"use client"

import { useEffect, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import { formatMoneyUnknown, formatRR } from "@/lib/formatDisplay"
import {
  COMMENT_PRIVATE_TRADE_DISCLAIMER,
  isPrivateTradeRow,
} from "@/lib/commentSharedTrade"

type CommentTradeAttachPickerProps = {
  open: boolean
  userId: string | null | undefined
  onClose: () => void
  onSelect: (trade: Record<string, unknown>) => void
}

export default function CommentTradeAttachPicker({
  open,
  userId,
  onClose,
  onSelect,
}: CommentTradeAttachPickerProps) {
  const [trades, setTrades] = useState<Record<string, unknown>[]>([])
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    if (!open || !userId) return
    let cancelled = false
    setLoading(true)
    void (async () => {
      const { data } = await supabase
        .from("trades")
        .select(
          "id, ticker, direction, pnl, rr, created_at, is_public, user_id"
        )
        .eq("user_id", userId)
        .order("created_at", { ascending: false })
        .limit(40)
      if (!cancelled) {
        setTrades((data as Record<string, unknown>[]) ?? [])
        setLoading(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [open, userId])

  if (!open) return null

  function handlePick(trade: Record<string, unknown>) {
    if (isPrivateTradeRow(trade)) {
      const ok = window.confirm(COMMENT_PRIVATE_TRADE_DISCLAIMER + "\n\nAttach this trade?")
      if (!ok) return
    }
    onSelect(trade)
    onClose()
  }

  return (
    <div
      className="fixed inset-0 z-[70] flex items-center justify-center bg-black/60 p-4"
      role="presentation"
      onClick={onClose}
    >
      <div
        className="w-full max-w-md rounded-2xl border border-white/10 bg-[#0f172a] p-4 text-white shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="mb-2 text-lg font-semibold text-blue-300">Attach trade</h2>
        <p className="mb-3 text-xs text-gray-400">
          Your public and private trades. Private trades are visible to everyone who can read this comment.
        </p>
        <div className="max-h-72 space-y-2 overflow-y-auto">
          {loading ? (
            <p className="text-sm text-gray-400">Loading trades…</p>
          ) : trades.length === 0 ? (
            <p className="text-sm text-gray-400">No trades to attach.</p>
          ) : (
            trades.map((trade) => {
              const id = String(trade.id ?? "")
              const privateRow = isPrivateTradeRow(trade)
              return (
                <button
                  key={id}
                  type="button"
                  onClick={() => handlePick(trade)}
                  className="w-full rounded-lg border border-white/10 bg-white/5 p-3 text-left hover:bg-white/10"
                >
                  <p className="font-medium">
                    {String(trade.ticker ?? "—")} • {String(trade.direction ?? "")}
                    {privateRow ? (
                      <span className="ml-2 text-xs font-normal text-gray-400">Private</span>
                    ) : null}
                  </p>
                  <p className="text-sm text-gray-400">
                    {formatMoneyUnknown(trade.pnl as number | null, { empty: "—" })} • RR{" "}
                    {formatRR(trade.rr as number | null)}
                  </p>
                </button>
              )
            })
          )}
        </div>
        <button
          type="button"
          onClick={onClose}
          className="mt-3 w-full rounded-lg bg-white/10 py-2 text-sm hover:bg-white/20"
        >
          Close
        </button>
      </div>
    </div>
  )
}