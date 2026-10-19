import {
  accountRowForTrade,
  tradeMatchesAccountFilter,
  type AccountRowForDisplay,
} from "./tradeAccountDisplay.ts"
import {
  filterTradesByPerformanceWindow,
  type PerformanceWindow,
} from "./performanceShare.ts"

export const TRADES_SELECTED_TRADE_PARAM = "trade"

const PERFORMANCE_WINDOWS = new Set<PerformanceWindow>([
  "daily",
  "weekly",
  "monthly",
  "yearly",
  "custom",
])

export type TradesPageViewFilters = {
  accountFilter: string
  accountTypeFilter: string
  timeframe: string
  selectedDate: string
  resultFilter: "all" | "wins" | "losses"
  showPublicOnly: boolean
  customRangeStart: string
  customRangeEnd: string
}

function tradeIsPublic(trade: { is_public?: unknown; public_description?: unknown }): boolean {
  if (trade?.is_public === true) return true
  const desc = trade?.public_description
  return typeof desc === "string" && desc.trim().length > 0
}

function tradeMatchesSelectedDate(
  trade: { created_at?: unknown },
  selectedDate: string
): boolean {
  if (!selectedDate) return true
  const tradeDate = new Date(String(trade.created_at ?? ""))
  const selected = new Date(`${selectedDate}T00:00:00`)
  if (Number.isNaN(tradeDate.getTime()) || Number.isNaN(selected.getTime())) {
    return false
  }
  return (
    tradeDate.getFullYear() === selected.getFullYear() &&
    tradeDate.getMonth() === selected.getMonth() &&
    tradeDate.getDate() === selected.getDate()
  )
}

function tradeMatchesTimeframe(
  trade: { created_at?: unknown },
  timeframe: string,
  customRangeStart: string,
  customRangeEnd: string
): boolean {
  if (!timeframe || timeframe === "all") return true
  if (!PERFORMANCE_WINDOWS.has(timeframe as PerformanceWindow)) return true
  return (
    filterTradesByPerformanceWindow([trade], timeframe as PerformanceWindow, {
      customRangeStart,
      customRangeEnd,
    }).length > 0
  )
}

function tradeMatchesResultFilter(
  trade: { pnl?: unknown },
  resultFilter: TradesPageViewFilters["resultFilter"]
): boolean {
  if (resultFilter === "wins") return Number(trade.pnl) > 0
  if (resultFilter === "losses") return Number(trade.pnl) < 0
  return true
}

function tradeMatchesModeFilter(
  trade: { mode?: unknown; account_type?: unknown },
  accountTypeFilter: string
): boolean {
  if (!accountTypeFilter || accountTypeFilter === "all") return true
  const tradeMode = String(trade.mode ?? trade.account_type ?? "")
    .toLowerCase()
    .trim()
  return tradeMode === accountTypeFilter.toLowerCase().trim()
}

/** `/trades` href that opens a trade in details view, not the editor. */
export function tradesSelectedTradeHref(tradeId: string | number | null | undefined): string {
  const id = String(tradeId ?? "").trim()
  if (!id) return "/trades"
  return `/trades?${TRADES_SELECTED_TRADE_PARAM}=${encodeURIComponent(id)}`
}

export function parseTradesSelectedTradeId(
  search: Pick<URLSearchParams, "get"> | string | null | undefined
): string | null {
  if (search == null) return null
  const raw =
    typeof search === "string"
      ? new URLSearchParams(search.startsWith("?") ? search.slice(1) : search).get(
          TRADES_SELECTED_TRADE_PARAM
        )
      : search.get(TRADES_SELECTED_TRADE_PARAM)
  const id = raw?.trim() ?? ""
  return id || null
}

/**
 * Widen only the Trades-page filters that would hide `trade`, so the selected
 * trade stays visible even when account, mode, or timeframe differ.
 */
export function tradesPageFiltersToRevealTrade(
  trade: {
    account_id?: unknown
    mode?: unknown
    account_type?: unknown
    created_at?: unknown
    pnl?: unknown
    is_public?: unknown
    public_description?: unknown
  },
  current: TradesPageViewFilters,
  opts?: {
    accountById?: Record<string, AccountRowForDisplay | null | undefined> | null
    copyGroupAccountIds?: readonly string[] | null
  }
): TradesPageViewFilters {
  const next: TradesPageViewFilters = { ...current }

  if (
    !tradeMatchesAccountFilter(
      trade,
      next.accountFilter,
      accountRowForTrade(trade, opts?.accountById ?? null),
      { copyGroupAccountIds: opts?.copyGroupAccountIds ?? undefined }
    )
  ) {
    next.accountFilter = "all"
  }

  if (!tradeMatchesModeFilter(trade, next.accountTypeFilter)) {
    next.accountTypeFilter = "all"
  }

  if (!tradeMatchesSelectedDate(trade, next.selectedDate)) {
    next.selectedDate = ""
  }

  if (!tradeMatchesResultFilter(trade, next.resultFilter)) {
    next.resultFilter = "all"
  }

  if (next.showPublicOnly && !tradeIsPublic(trade)) {
    next.showPublicOnly = false
  }

  if (
    !tradeMatchesTimeframe(
      trade,
      next.timeframe,
      next.customRangeStart,
      next.customRangeEnd
    )
  ) {
    next.timeframe = "all"
    next.customRangeStart = ""
    next.customRangeEnd = ""
  }

  return next
}
