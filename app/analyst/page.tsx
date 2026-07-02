"use client"

import Navbar from "../components/Navbar"
import LockedFeature from "../components/LockedFeature"
import { useCallback, useEffect, useState, Suspense } from "react"
import { useSearchParams } from "next/navigation"
import { supabase } from "../../lib/supabaseClient"
import { isProActive } from "../../lib/subscription"
import { formatEST } from "@/lib/formatEST"
import { formatRR } from "@/lib/formatDisplay"
import {
  formatTradeAccountDisplay,
  safeAccountNumberLabel,
} from "@/lib/tradeAccountDisplay"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { useCachedTrades } from "@/lib/useAppDataCache"
import { getCachedTrades, upsertTradeInCache } from "@/lib/appDataCache"
import { SkeletonTradesPageContent } from "../components/ui/skeletons"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"

type AnalyzeTradeApiPayload = {
  reply?: string
  error?: string
}

async function parseAnalyzeTradeResponse(res: Response): Promise<{
  ok: boolean
  data: AnalyzeTradeApiPayload | null
}> {
  const text = await res.text()

  if (!text.trim()) {
    return {
      ok: false,
      data: {
        error: res.ok
          ? "Analysis returned an empty response. Please try again."
          : "Analysis is temporarily unavailable. Please try again.",
      },
    }
  }

  try {
    return { ok: res.ok, data: JSON.parse(text) as AnalyzeTradeApiPayload }
  } catch {
    return {
      ok: false,
      data: {
        error: "Analysis returned an invalid response. Please try again.",
      },
    }
  }
}

function analyzeTradeErrorMessage(
  data: AnalyzeTradeApiPayload | null,
  fallback: string
) {
  return data?.reply?.trim() || data?.error?.trim() || fallback
}

export default function AnalystPage() {
  return (
    <Suspense
      fallback={
        <>
          <Navbar />
          <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-10">
            <SkeletonTradesPageContent tradeCount={4} />
          </div>
        </>
      }
    >
      <AnalystPageContent />
    </Suspense>
  )
}

function AnalystPageContent() {
  const { user, profile, loading: profileLoading } = useUserProfile()
  const { trades, loading: tradesLoading } = useCachedTrades(user?.id)
  const pageReady =
    (!profileLoading || profile != null) &&
    !(tradesLoading && trades.length === 0 && getCachedTrades(user?.id) == null)
  const [selectedTrade, setSelectedTrade] = useState<any>(null)

  const [messages, setMessages] = useState<any[]>([])
  const [input, setInput] = useState("")
  const [loading, setLoading] = useState(false)
  const [tradePanelExpanded, setTradePanelExpanded] = useState(true)
  const searchParams = useSearchParams()

  function formatCurrency(val: number) {
    if (val === null || val === undefined) return "-"
    return `${val < 0 ? "-" : ""}$${Math.abs(val).toLocaleString()}`
  }

  function tradeScreenshotUrl(trade: any) {
    if (!trade?.image_url) return null
    if (String(trade.image_url).startsWith("http")) return trade.image_url
    return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${trade.image_url}`
  }

  function formatTradeSummaryDate(createdAt: string) {
    const date = new Date(createdAt)
    if (Number.isNaN(date.getTime())) return "—"
    return date.toLocaleDateString("en-US", {
      month: "numeric",
      day: "numeric",
      year: "2-digit",
    })
  }

  function formatPnlSummary(val: number) {
    const formatted = formatCurrency(val)
    if (val > 0) return `+${formatted}`
    return formatted
  }

  function selectedTradeSummaryLine(trade: any) {
    const direction = trade.direction || "—"
    return `${trade.ticker} ${direction} • ${formatPnlSummary(trade.pnl)} • ${formatTradeSummaryDate(trade.created_at)}`
  }

  const selectTradeForReview = useCallback(
    (trade: any) => {
      if (!isProActive(profile)) return

      setSelectedTrade(trade)
      setInput("")
      if (trade.ai_feedback) {
        setMessages([{ role: "assistant", content: trade.ai_feedback }])
        setTradePanelExpanded(false)
      } else {
        setMessages([])
        setTradePanelExpanded(true)
      }
    },
    [profile]
  )

  useEffect(() => {
    if (!pageReady || trades.length === 0) return

    const tradeId = searchParams.get("trade")?.trim()
    if (!tradeId) return

    const trade = trades.find((t) => String(t.id) === tradeId)
    if (trade && String(selectedTrade?.id) !== tradeId) {
      selectTradeForReview(trade)
    }
  }, [pageReady, trades, searchParams, selectedTrade?.id, selectTradeForReview])

  async function runTradeAnalysis() {
    if (!selectedTrade || !isProActive(profile) || loading) return
    if (selectedTrade.ai_feedback) return
    if (isDemoModeActive()) {
      requestDemoSignup("ai")
      return
    }

    const trade = selectedTrade
    setLoading(true)
    setTradePanelExpanded(false)

    const {
      data: { session },
    } = await supabase.auth.getSession()
    console.log("AI TOKEN:", session?.access_token)

    const pnl = trade?.pnl
    const rr = trade?.rr
    const notes = trade?.notes
    const confluences = trade?.confluences ?? trade?.top_confluences
    const mistakes = trade?.mistakes
    const psychology = trade?.psychology ?? trade?.psychology_notes
    const entry_price = trade?.entry_price
    const exit_price = trade?.exit_price
    const direction = trade?.direction
    console.log("AI INPUT:", {
      pnl,
      rr,
      notes,
      confluences,
      mistakes,
      psychology,
      entry_price,
      exit_price,
      direction,
    })

    const res = await fetch("/api/analyze-trade", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${session?.access_token}`,
      },
      body: JSON.stringify({
        trade,
        messages: [],
      }),
    })

    const { ok, data } = await parseAnalyzeTradeResponse(res)

    if (!ok || !data?.reply) {
      const errorMessage = analyzeTradeErrorMessage(
        data,
        "We couldn't complete the analysis. Please try again."
      )
      setMessages([{ role: "assistant", content: errorMessage }])
      setLoading(false)
      return
    }

    const reply = data.reply
    setMessages([{ role: "assistant", content: reply }])
    if (user?.id) {
      upsertTradeInCache(user.id, { ...trade, ai_feedback: reply })
    }
    setSelectedTrade((s) =>
      s && String(s.id) === String(trade.id) ? { ...s, ai_feedback: reply } : s
    )
    setLoading(false)
  }

  async function sendMessage() {
    if (!input.trim() || !selectedTrade) return
    if (!isProActive(profile)) return
    if (isDemoModeActive()) {
      requestDemoSignup("ai")
      return
    }

    const newMessages = [...messages, { role: "user", content: input }]

    setMessages(newMessages)
    setInput("")
    setLoading(true)

    const {
      data: { session },
    } = await supabase.auth.getSession()
    console.log("AI TOKEN:", session?.access_token)

    const t = selectedTrade
    const pnl = t?.pnl
    const rr = t?.rr
    const notes = t?.notes
    const confluences = t?.confluences ?? t?.top_confluences
    const mistakes = t?.mistakes
    const psychology = t?.psychology ?? t?.psychology_notes
    const entry_price = t?.entry_price
    const exit_price = t?.exit_price
    const direction = t?.direction
    console.log("AI INPUT:", {
      pnl,
      rr,
      notes,
      confluences,
      mistakes,
      psychology,
      entry_price,
      exit_price,
      direction,
    })

    const res = await fetch("/api/analyze-trade", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${session?.access_token}`,
      },
      body: JSON.stringify({
        trade: selectedTrade,
        messages: newMessages,
      }),
    })

    const { ok, data } = await parseAnalyzeTradeResponse(res)

    if (!ok || !data?.reply) {
      setMessages([
        ...newMessages,
        {
          role: "assistant",
          content: analyzeTradeErrorMessage(
            data,
            "We couldn't complete the analysis. Please try again."
          ),
        },
      ])
      setLoading(false)
      return
    }

    setMessages([...newMessages, { role: "assistant", content: data.reply }])
    if (user?.id && selectedTrade) {
      upsertTradeInCache(user.id, {
        ...selectedTrade,
        ai_feedback: data.reply,
      })
    }
    setSelectedTrade((s) =>
      s && String(s.id) === String(selectedTrade.id)
        ? { ...s, ai_feedback: data.reply }
        : s
    )

    setLoading(false)
  }

  const pro = isProActive(profile)

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 p-10">
        <h1 className="mb-8 text-center text-3xl bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
          AI Trade Analyst
        </h1>

        {!pageReady ? (
          <SkeletonTradesPageContent tradeCount={4} />
        ) : !pro ? (
          <div className="mx-auto max-w-lg">
            <LockedFeature title="AI Analyst" />
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-8 lg:grid-cols-2">
            <div className="max-h-[80vh] overflow-y-auto rounded-xl border border-white/10 bg-white/5 p-4">
              {trades.map((trade) => (
                <div
                  key={trade.id}
                  onClick={() => selectTradeForReview(trade)}
                  className={`mb-3 cursor-pointer rounded border p-4 ${
                    selectedTrade?.id === trade.id
                      ? "border-emerald-400 bg-white/10"
                      : "border-white/10 hover:bg-white/10"
                  }`}
                >
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="font-semibold">
                        {trade.ticker} • {trade.direction}
                      </p>

                      <p className="text-xs text-gray-400">
                        {formatEST(trade.created_at)} • {trade.session}
                      </p>

                      <p className="text-xs text-gray-500">
                        {formatTradeAccountDisplay(trade) || "—"}
                      </p>
                    </div>

                    <div className="text-right">
                      <p
                        className={
                          trade.pnl >= 0 ? "text-green-400" : "text-red-400"
                        }
                      >
                        {formatCurrency(trade.pnl)}
                      </p>

                      <p className="text-xs text-gray-400">
                        RR: {formatRR(trade.rr, "-")}
                        {trade.contracts != null
                          ? ` • Contracts: ${trade.contracts}`
                          : ""}
                      </p>

                      {trade.ai_feedback && (
                        <span className="mt-1 inline-block text-xs text-green-400">
                          Analyzed
                        </span>
                      )}
                    </div>
                  </div>
                </div>
              ))}
            </div>

            <div className="flex h-[80vh] flex-col rounded-xl border border-white/10 bg-white/5 p-4">
              {!selectedTrade && (
                <p className="mt-10 text-center text-gray-400">Select a trade</p>
              )}

              {selectedTrade && (
                <>
                  <div className="mb-4 shrink-0 rounded-xl border border-white/10 bg-[#0f172a]/60 p-4">
                    <button
                      type="button"
                      onClick={() => setTradePanelExpanded((expanded) => !expanded)}
                      className="flex w-full items-start justify-between gap-3 text-left"
                      aria-expanded={tradePanelExpanded}
                    >
                      <div className="min-w-0 flex-1">
                        <p className="text-xs font-medium uppercase tracking-wide text-gray-400">
                          Selected Trade{" "}
                          <span className="normal-case tracking-normal text-gray-500">
                            {tradePanelExpanded
                              ? "(Click to Collapse)"
                              : "(Click to Expand)"}
                          </span>
                        </p>
                        {!tradePanelExpanded ? (
                          <p className="mt-1 truncate text-sm font-semibold text-gray-100">
                            {selectedTradeSummaryLine(selectedTrade)}
                          </p>
                        ) : null}
                      </div>
                      <span
                        className="shrink-0 text-sm text-gray-400"
                        aria-hidden
                      >
                        {tradePanelExpanded ? "▲" : "▼"}
                      </span>
                    </button>

                    {tradePanelExpanded ? (
                      <>
                        <p className="mt-3 text-lg font-semibold">
                          {selectedTrade.ticker}{" "}
                          {selectedTrade.direction || "—"}
                        </p>
                        <p
                          className={`mt-1 text-xl font-bold ${
                            selectedTrade.pnl >= 0
                              ? "text-green-400"
                              : "text-red-400"
                          }`}
                        >
                          {formatCurrency(selectedTrade.pnl)}
                        </p>
                        <p className="mt-1 text-sm text-gray-400">
                          {formatEST(selectedTrade.created_at)}
                          {selectedTrade.session
                            ? ` • ${selectedTrade.session}`
                            : ""}
                        </p>

                        <div className="mt-3 space-y-1 border-t border-white/10 pt-3 text-sm">
                          <p className="text-gray-400">
                            {formatTradeAccountDisplay(selectedTrade) || "—"}
                          </p>

                          {(selectedTrade.entry_price != null ||
                            selectedTrade.exit_price != null) && (
                            <p>
                              <span className="text-gray-400">Entry:</span>{" "}
                              {selectedTrade.entry_price ?? "—"} →{" "}
                              <span className="text-gray-400">Exit:</span>{" "}
                              {selectedTrade.exit_price ?? "—"}
                            </p>
                          )}

                          {selectedTrade.contracts != null && (
                            <p>
                              <span className="text-gray-400">Contracts:</span>{" "}
                              {selectedTrade.contracts}
                            </p>
                          )}

                          <p>
                            <span className="text-gray-400">RR:</span>{" "}
                            {formatRR(selectedTrade.rr, "—")}
                          </p>

                          {selectedTrade.notes ? (
                            <p>
                              <span className="text-gray-400">Notes:</span>{" "}
                              <span className="italic text-gray-300">
                                {selectedTrade.notes}
                              </span>
                            </p>
                          ) : null}

                          {(selectedTrade.confluences ??
                            selectedTrade.top_confluences) ? (
                            <p>
                              <span className="text-gray-400">Confluences:</span>{" "}
                              {Array.isArray(
                                selectedTrade.confluences ??
                                  selectedTrade.top_confluences
                              )
                                ? (
                                    selectedTrade.confluences ??
                                    selectedTrade.top_confluences
                                  ).join(", ")
                                : String(
                                    selectedTrade.confluences ??
                                      selectedTrade.top_confluences
                                  )}
                            </p>
                          ) : null}

                          {selectedTrade.mistakes ? (
                            <p>
                              <span className="text-gray-400">Mistakes:</span>{" "}
                              {Array.isArray(selectedTrade.mistakes)
                                ? selectedTrade.mistakes.join(", ")
                                : String(selectedTrade.mistakes)}
                            </p>
                          ) : null}

                          {(selectedTrade.psychology ??
                            selectedTrade.psychology_notes) ? (
                            <p>
                              <span className="text-gray-400">Psychology:</span>{" "}
                              {selectedTrade.psychology ??
                                selectedTrade.psychology_notes}
                            </p>
                          ) : null}
                        </div>

                        {tradeScreenshotUrl(selectedTrade) ? (
                          <img
                            src={tradeScreenshotUrl(selectedTrade)!}
                            className="mt-3 max-h-48 w-full rounded border border-white/10 object-cover"
                            alt=""
                            loading="lazy"
                            decoding="async"
                          />
                        ) : null}
                      </>
                    ) : null}
                  </div>

                  {!selectedTrade.ai_feedback && messages.length === 0 && (
                    <div className="mb-4 shrink-0 rounded-xl border border-emerald-400/30 bg-emerald-500/10 p-4 text-center">
                      <p className="mb-3 text-sm text-gray-300">
                        Ready for Analysis
                      </p>
                      <button
                        type="button"
                        onClick={() => void runTradeAnalysis()}
                        disabled={loading}
                        className="rounded-lg bg-emerald-500 px-6 py-2.5 text-sm font-semibold text-white transition hover:bg-emerald-600 disabled:cursor-not-allowed disabled:opacity-60"
                      >
                        {loading ? "Analyzing…" : "Analyze Trade"}
                      </button>
                    </div>
                  )}

                  {(messages.length > 0 || loading) && (
                    <div className="mb-4 flex min-h-0 flex-1 flex-col space-y-4 overflow-y-auto">
                      {messages.map((msg, i) => (
                        <div
                          key={i}
                          className={`max-w-[95%] rounded p-3 ${
                            msg.role === "user"
                              ? "ml-auto bg-blue-500"
                              : "bg-white/10"
                          }`}
                        >
                          <div className="whitespace-pre-wrap text-sm leading-relaxed md:text-base">
                            {msg.content}
                          </div>
                        </div>
                      ))}

                      {loading && (
                        <p className="text-gray-400">Analyzing...</p>
                      )}
                    </div>
                  )}

                  {messages.length > 0 && (
                    <div className="flex shrink-0 gap-2">
                      <input
                        value={input}
                        onChange={(e) => setInput(e.target.value)}
                        placeholder="Ask about this trade..."
                        className="flex-1 rounded border border-white/10 bg-[#0f172a] p-2"
                        disabled={loading}
                      />

                      <button
                        type="button"
                        onClick={() => void sendMessage()}
                        disabled={loading}
                        className="rounded bg-emerald-500 px-4 disabled:opacity-60"
                      >
                        Send
                      </button>
                    </div>
                  )}
                </>
              )}
            </div>
          </div>
        )}
      </div>
    </>
  )
}
