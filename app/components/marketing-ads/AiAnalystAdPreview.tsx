"use client"

import { formatEST } from "@/lib/formatEST"
import { formatRR } from "@/lib/formatDisplay"
import { formatTradeAccountDisplay } from "@/lib/tradeAccountDisplay"
import { DEMO_AI_FEEDBACK, DEMO_TRADES } from "@/lib/demo/fixtures"
import InstagramAdShell from "./InstagramAdShell"

function formatCurrency(val: number) {
  const abs = Math.abs(val)
  const formatted = abs.toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
  return val < 0 ? `-$${formatted}` : `$${formatted}`
}

/** Mirrors the real analyst trade + AI reply panel styling with demo feedback. */
export default function AiAnalystAdPreview() {
  const trade = DEMO_TRADES.find((t) => t.id === "dt-24") ?? DEMO_TRADES[0]
  const feedback = trade.ai_feedback || DEMO_AI_FEEDBACK

  return (
    <InstagramAdShell
      title="Review Every Trade With AI"
      subtitle="Get personalized strengths, weaknesses, and improvement areas from your actual trading history."
      settleMs={800}
    >
      <div className="overflow-hidden rounded-2xl border border-white/10 bg-[#0b1220]/70 shadow-xl shadow-black/30 backdrop-blur-md">
        <div className="border-b border-white/10 px-5 py-3">
          <p className="text-xs font-semibold uppercase tracking-wide text-blue-300">
            AI Trade Analyst
          </p>
        </div>

        <div className="space-y-4 p-5">
          <div className="rounded-xl border border-white/10 bg-[#0f172a]/60 p-4">
            <p className="text-xs font-medium uppercase tracking-wide text-gray-400">
              Selected Trade
            </p>
            <p className="mt-2 text-lg font-semibold text-white">
              {trade.ticker} {trade.direction || "—"}
            </p>
            <p
              className={`mt-1 text-xl font-bold ${
                Number(trade.pnl) >= 0 ? "text-green-400" : "text-red-400"
              }`}
            >
              {formatCurrency(Number(trade.pnl) || 0)}
            </p>
            <p className="mt-1 text-sm text-gray-400">
              {formatEST(trade.created_at)}
              {trade.session ? ` • ${trade.session}` : ""}
            </p>
            <div className="mt-3 space-y-1 border-t border-white/10 pt-3 text-sm text-gray-300">
              <p className="text-gray-400">
                {formatTradeAccountDisplay(trade) || "—"}
              </p>
              <p>
                <span className="text-gray-400">Entry:</span>{" "}
                {trade.entry_price ?? "—"} →{" "}
                <span className="text-gray-400">Exit:</span>{" "}
                {trade.exit_price ?? "—"}
              </p>
              <p>
                <span className="text-gray-400">RR:</span>{" "}
                {formatRR(trade.rr, "—")}
              </p>
            </div>
          </div>

          <div className="max-h-[560px] overflow-hidden rounded-xl bg-white/10 p-4">
            <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-emerald-300/90">
              AI Analysis
            </div>
            <div className="whitespace-pre-wrap text-[15px] leading-relaxed text-gray-100">
              {feedback}
            </div>
          </div>
        </div>
      </div>
    </InstagramAdShell>
  )
}
