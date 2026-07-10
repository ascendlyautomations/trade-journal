"use client"

import Link from "next/link"
import LockedFeature from "../components/LockedFeature"
import { useCallback, useEffect, useRef, useState, Suspense, type Dispatch, type ReactNode, type SetStateAction } from "react"
import { createPortal } from "react-dom"
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
import { SkeletonAnalystPanel } from "../components/ui/skeletons"
import EmptyState from "../components/ui/EmptyState"
import { NAVBAR_HEIGHT_CLASS } from "@/app/components/ui/DetailModalShell"
import ModalCloseButton from "@/app/components/ui/ModalCloseButton"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import AnalyzeTradeProgressModal from "../components/analyst/AnalyzeTradeProgressModal"
import { createAnalyzeProgressController } from "@/lib/analyzeTradeProgress"
import { tradeScreenshotPublicUrl } from "@/lib/storagePublicUrl"
import { notifyGettingStartedChecklistMaybeCompleted } from "@/lib/gettingStartedProgressSync"

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

const MOBILE_ANALYST_MQ = "(max-width: 1023px)"

function isMobileAnalystViewport() {
  if (typeof window === "undefined") return false
  return window.matchMedia(MOBILE_ANALYST_MQ).matches
}

type AnalystTradeDetailPanelProps = {
  selectedTrade: any
  tradePanelExpanded: boolean
  setTradePanelExpanded: Dispatch<SetStateAction<boolean>>
  messages: any[]
  loading: boolean
  analysisInProgress?: boolean
  input: string
  setInput: (value: string) => void
  onRunAnalysis: () => void
  onSendMessage: () => void
  formatCurrency: (val: number) => string
  selectedTradeSummaryLine: (trade: any) => string
  tradeScreenshotUrl: (trade: any) => string | null
  showTradeDetailsPanel?: boolean
  emptyState?: ReactNode
  className?: string
  /** When true, the parent owns vertical scroll (mobile full-screen modal). */
  embeddedInScrollContainer?: boolean
}

function AnalystCompactTradeHeader({
  trade,
  formatCurrency,
  formatTradeSummaryDate,
  className = "",
}: {
  trade: any
  formatCurrency: (val: number) => string
  formatTradeSummaryDate: (createdAt: string) => string
  className?: string
}) {
  return (
    <div className={`min-w-0 flex-1 ${className}`}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate text-sm font-semibold text-gray-100">
            {trade.ticker} • {trade.direction || "—"}
          </p>
          <p className="mt-0.5 text-xs text-gray-400">
            {formatTradeSummaryDate(trade.created_at)}
          </p>
        </div>
        <div className="shrink-0 text-right">
          <p
            className={`text-sm font-semibold ${
              trade.pnl >= 0 ? "text-green-400" : "text-red-400"
            }`}
          >
            {formatCurrency(trade.pnl)}
          </p>
          <p className="mt-0.5 text-xs text-gray-400">
            RR: {formatRR(trade.rr, "—")}
          </p>
        </div>
      </div>
    </div>
  )
}

function AnalystTradeDetailPanel({
  selectedTrade,
  tradePanelExpanded,
  setTradePanelExpanded,
  messages,
  loading,
  analysisInProgress = false,
  input,
  setInput,
  onRunAnalysis,
  onSendMessage,
  formatCurrency,
  selectedTradeSummaryLine,
  tradeScreenshotUrl,
  showTradeDetailsPanel = true,
  emptyState,
  className = "",
  embeddedInScrollContainer = false,
}: AnalystTradeDetailPanelProps) {
  if (!selectedTrade) {
    return (
      emptyState ?? (
        <p className="mt-10 text-center text-gray-400">Select a trade</p>
      )
    )
  }

  return (
    <div
      className={`flex flex-col ${
        embeddedInScrollContainer ? "" : "min-h-0 flex-1"
      } ${className}`}
    >
      {showTradeDetailsPanel ? (
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
            <span className="shrink-0 text-sm text-gray-400" aria-hidden>
              {tradePanelExpanded ? "▲" : "▼"}
            </span>
          </button>

          {tradePanelExpanded ? (
            <>
              <p className="mt-3 text-lg font-semibold">
                {selectedTrade.ticker} {selectedTrade.direction || "—"}
              </p>
              <p
                className={`mt-1 text-xl font-bold ${
                  selectedTrade.pnl >= 0 ? "text-green-400" : "text-red-400"
                }`}
              >
                {formatCurrency(selectedTrade.pnl)}
              </p>
              <p className="mt-1 text-sm text-gray-400">
                {formatEST(selectedTrade.created_at)}
                {selectedTrade.session ? ` • ${selectedTrade.session}` : ""}
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
                    {selectedTrade.psychology ?? selectedTrade.psychology_notes}
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
      ) : null}

      {!selectedTrade.ai_feedback && messages.length === 0 && (
        <div className="mb-4 shrink-0 rounded-xl border border-emerald-400/30 bg-emerald-500/10 p-4 text-center">
          <p className="mb-3 text-sm text-gray-300">Ready for Analysis</p>
          <button
            type="button"
            onClick={onRunAnalysis}
            disabled={loading || analysisInProgress}
            className="rounded-lg bg-blue-500 px-6 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:bg-blue-500"
          >
            {analysisInProgress ? "Analyzing…" : "Analyze Trade"}
          </button>
        </div>
      )}

      {messages.length > 0 && (
        <div
          className={`mb-4 flex flex-col space-y-4 ${
            embeddedInScrollContainer
              ? ""
              : "min-h-0 flex-1 overflow-y-auto overscroll-contain"
          }`}
        >
          {messages.map((msg, i) => (
            <div
              key={i}
              className={`max-w-[95%] rounded p-3 ${
                msg.role === "user" ? "ml-auto bg-blue-500" : "bg-white/10"
              }`}
            >
              <div className="whitespace-pre-wrap text-sm leading-relaxed md:text-base">
                {msg.content}
              </div>
            </div>
          ))}

          {loading ? <p className="text-gray-400">Thinking...</p> : null}
        </div>
      )}

      {messages.length > 0 ? (
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
            onClick={onSendMessage}
            disabled={loading}
            className="rounded bg-blue-500 px-4 hover:bg-blue-600 disabled:opacity-60 disabled:hover:bg-blue-500"
          >
            Send
          </button>
        </div>
      ) : null}
    </div>
  )
}

type AnalystMobileAnalysisSheetProps = Omit<
  AnalystTradeDetailPanelProps,
  "showTradeDetailsPanel" | "emptyState" | "className"
> & {
  open: boolean
  onClose: () => void
  formatTradeSummaryDate: (createdAt: string) => string
}

function AnalystMobileAnalysisSheet({
  open,
  onClose,
  selectedTrade,
  formatCurrency,
  formatTradeSummaryDate,
  ...panelProps
}: AnalystMobileAnalysisSheetProps) {
  const [mounted, setMounted] = useState(false)
  const touchStartY = useRef<number | null>(null)

  useEffect(() => {
    setMounted(true)
  }, [])

  useModalScrollLock(open)

  useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, onClose])

  if (!open || !mounted || !selectedTrade) return null

  function handleTouchStart(e: React.TouchEvent) {
    touchStartY.current = e.touches[0]?.clientY ?? null
  }

  function handleTouchEnd(e: React.TouchEvent) {
    const startY = touchStartY.current
    touchStartY.current = null
    if (startY == null) return
    const endY = e.changedTouches[0]?.clientY
    if (endY != null && endY - startY > 72) onClose()
  }

  return createPortal(
    <div
      className={`fixed inset-x-0 bottom-0 ${NAVBAR_HEIGHT_CLASS} z-[9000] flex flex-col overflow-hidden bg-[#0f172a] text-gray-100 lg:hidden`}
      role="dialog"
      aria-modal="true"
      aria-label="Trade analysis"
    >
      <header
        className="flex shrink-0 items-start gap-3 border-b border-white/10 bg-[#0f172a] px-4 py-3"
        onTouchStart={handleTouchStart}
        onTouchEnd={handleTouchEnd}
      >
        <AnalystCompactTradeHeader
          trade={selectedTrade}
          formatCurrency={formatCurrency}
          formatTradeSummaryDate={formatTradeSummaryDate}
        />
        <ModalCloseButton onClick={onClose} />
      </header>

      <div className="flex min-h-0 flex-1 flex-col overflow-y-auto overscroll-contain px-4 pb-[max(1rem,env(safe-area-inset-bottom))] pt-3">
        <AnalystTradeDetailPanel
          {...panelProps}
          selectedTrade={selectedTrade}
          formatCurrency={formatCurrency}
          showTradeDetailsPanel={false}
          embeddedInScrollContainer
        />
      </div>
    </div>,
    document.body
  )
}

export default function AnalystPage() {
  return (
    <Suspense
      fallback={
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-10">
          <h1 className="mb-8 text-center text-3xl text-blue-300">
            AI Analyst
          </h1>
          <SkeletonAnalystPanel count={4} />
        </div>
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
  const [analysisInProgress, setAnalysisInProgress] = useState(false)
  const [progressOpen, setProgressOpen] = useState(false)
  const [progressPercent, setProgressPercent] = useState(0)
  const [progressLabel, setProgressLabel] = useState("Preparing analysis...")
  const analysisRunningRef = useRef(false)
  const [tradePanelExpanded, setTradePanelExpanded] = useState(true)
  const [mobileAnalysisOpen, setMobileAnalysisOpen] = useState(false)
  const searchParams = useSearchParams()

  function formatCurrency(val: number) {
    if (val === null || val === undefined) return "-"
    return `${val < 0 ? "-" : ""}$${Math.abs(val).toLocaleString()}`
  }

  function tradeScreenshotUrl(trade: any) {
    return tradeScreenshotPublicUrl(trade?.image_url)
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
      if (isMobileAnalystViewport()) {
        setMobileAnalysisOpen(true)
      }
    },
    [profile]
  )

  const closeMobileAnalysis = useCallback(() => {
    setMobileAnalysisOpen(false)
  }, [])

  useEffect(() => {
    const mq = window.matchMedia(MOBILE_ANALYST_MQ)
    function onViewportChange() {
      if (!mq.matches) setMobileAnalysisOpen(false)
    }
    mq.addEventListener("change", onViewportChange)
    return () => mq.removeEventListener("change", onViewportChange)
  }, [])

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
    if (!selectedTrade || !isProActive(profile)) return
    if (selectedTrade.ai_feedback) return
    if (analysisRunningRef.current || analysisInProgress || loading) return
    if (isDemoModeActive()) {
      requestDemoSignup("ai")
      return
    }

    const trade = selectedTrade
    const hasScreenshot = Boolean(tradeScreenshotUrl(trade))
    analysisRunningRef.current = true
    setAnalysisInProgress(true)
    setTradePanelExpanded(false)
    setProgressPercent(0)
    setProgressLabel("Preparing analysis...")
    setProgressOpen(true)

    const controller = createAnalyzeProgressController(
      hasScreenshot,
      (percent, label) => {
        setProgressPercent(percent)
        setProgressLabel(label)
      }
    )
    controller.start()

    const {
      data: { session },
    } = await supabase.auth.getSession()

    try {
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
      notifyGettingStartedChecklistMaybeCompleted()
    } finally {
      controller.markApiComplete()
      await controller.waitForCompletion()
      controller.stop()
      setProgressOpen(false)
      setAnalysisInProgress(false)
      analysisRunningRef.current = false
    }
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
    notifyGettingStartedChecklistMaybeCompleted()

    setLoading(false)
  }

  const pro = isProActive(profile)

  const panelProps = {
    selectedTrade,
    tradePanelExpanded,
    setTradePanelExpanded,
    messages,
    loading,
    analysisInProgress,
    input,
    setInput,
    onRunAnalysis: () => void runTradeAnalysis(),
    onSendMessage: () => void sendMessage(),
    formatCurrency,
    selectedTradeSummaryLine,
    tradeScreenshotUrl,
  }

  return (
    <>
      <AnalyzeTradeProgressModal
        open={progressOpen}
        percent={progressPercent}
        status={progressLabel}
      />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 p-10">
        <h1 className="mb-8 text-center text-3xl text-blue-300">
          AI Analyst
        </h1>

        {!pageReady ? (
          <SkeletonAnalystPanel count={4} />
        ) : !pro ? (
          <div className="mx-auto max-w-lg">
            <LockedFeature title="AI Analyst" />
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-8 lg:grid-cols-2">
            <div className="max-h-[80vh] overflow-y-auto rounded-xl border border-white/10 bg-white/5 p-4">
              {trades.length === 0 ? (
                <EmptyState
                  icon="🤖"
                  title="No Trades to Analyze"
                  description="Add your first trade to unlock AI-powered trade review and coaching."
                  action={
                    <Link
                      href="/app"
                      className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
                    >
                      Add Trade
                    </Link>
                  }
                  className="py-10"
                />
              ) : (
              trades.map((trade) => (
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
              ))
              )}
            </div>

            <div className="hidden h-[80vh] flex-col rounded-xl border border-white/10 bg-white/5 p-4 lg:flex">
              <AnalystTradeDetailPanel
                {...panelProps}
                emptyState={
                  <p className="mt-10 text-center text-gray-400">Select a trade</p>
                }
              />
            </div>
          </div>
        )}

        <AnalystMobileAnalysisSheet
          open={mobileAnalysisOpen && pro && pageReady}
          onClose={closeMobileAnalysis}
          formatTradeSummaryDate={formatTradeSummaryDate}
          {...panelProps}
        />
      </div>
    </>
  )
}
