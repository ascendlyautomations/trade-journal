import type { ManualPayoutLedgerEntry } from "@/lib/accountPayoutEntry"
import { isPropFirmTradingAccount } from "@/lib/accountPayoutPolicy"
import { supportsLiveWithdrawal } from "@/lib/accountPayoutPolicy"
import { parseAccountSizeToNumber } from "@/lib/propfirmMetrics"
import {
  formatDashboardEquityCurvePointDate,
  resolveDashboardPeriodStartMs,
  resolveDashboardPeriodEndMs,
  type DashboardEquityChartPoint,
  type DashboardEquityPeriodContext,
} from "@/lib/dashboardLiveAccountValue"
import {
  resolveDashboardTradeDate,
  tradeMatchesDashboardSelectedDate,
  tradeMatchesDashboardTimeFilter,
  type DashboardTradeDateFields,
} from "@/lib/dashboardTradeDate"
import { getTradingDayKey } from "@/lib/formatDate"
import { excludeBacktestTrades } from "@/lib/tradeModeFilters"

export type LivePersonalDrawdownType = "fixed" | "trailing"

import {
  parseWithdrawalDrawdownBehaviorFromNote,
  type LiveWithdrawalDrawdownBehavior,
} from "@/lib/livePersonalDrawdownNote"

export type { LiveWithdrawalDrawdownBehavior } from "@/lib/livePersonalDrawdownNote"
export {
  encodeWithdrawalDrawdownNote,
  stripWithdrawalDrawdownNotePrefix,
} from "@/lib/livePersonalDrawdownNote"

export type LivePersonalDrawdownConfig = {
  limitAmount: number
  limitType: LivePersonalDrawdownType
}

export type LivePersonalDrawdownAccountRow = {
  category?: unknown
  mode?: unknown
  account_size?: unknown
  max_drawdown?: unknown
  drawdown_type?: unknown
}

export type LivePersonalDrawdownChartPoint = DashboardEquityChartPoint & {
  drawdownFloor: number | null
}

type TimelineEvent = {
  sortMs: number
  date: string
  kind: "trade" | "withdrawal"
  delta: number
  withdrawalBehavior?: LiveWithdrawalDrawdownBehavior | null
}

function mapDrawdownType(raw: unknown): LivePersonalDrawdownType | null {
  const t = String(raw ?? "")
    .trim()
    .toLowerCase()
  if (t === "static") return "fixed"
  if (
    t === "trailing" ||
    t === "end_of_day_trailing" ||
    t === "intraday_trailing"
  ) {
    return "trailing"
  }
  return null
}

export function parseLivePersonalDrawdownConfigFromAccount(
  account: LivePersonalDrawdownAccountRow | null | undefined
): LivePersonalDrawdownConfig | null {
  if (!account || !supportsLiveWithdrawal(account)) return null
  if (isPropFirmTradingAccount(account)) return null

  const limit = Number(account.max_drawdown)
  if (!Number.isFinite(limit) || limit <= 0) return null

  const limitType =
    mapDrawdownType(account.drawdown_type) ?? ("fixed" as const)

  return { limitAmount: limit, limitType }
}

/** Dashboard gear panel: always from `accounts` row (never profile). */
export function readLivePersonalDrawdownGearFromAccount(
  account: LivePersonalDrawdownAccountRow | null | undefined
): {
  limitType: LivePersonalDrawdownType
  /** Raw persisted amount string, or "" when unset/cleared. */
  limitAmountRaw: string
} {
  if (!account || !supportsLiveWithdrawal(account)) {
    return { limitType: "fixed", limitAmountRaw: "" }
  }
  if (isPropFirmTradingAccount(account)) {
    return { limitType: "fixed", limitAmountRaw: "" }
  }

  const limitType = mapDrawdownType(account.drawdown_type) ?? "fixed"
  const limit = Number(account.max_drawdown)
  const limitAmountRaw =
    account.max_drawdown != null &&
    account.max_drawdown !== "" &&
    Number.isFinite(limit) &&
    limit > 0
      ? String(limit)
      : ""

  return { limitType, limitAmountRaw }
}

export function livePersonalDrawdownTypeToAccountDrawdownType(
  type: LivePersonalDrawdownType
): "static" | "end_of_day_trailing" {
  return type === "fixed" ? "static" : "end_of_day_trailing"
}

function payoutDateToSortMs(payoutDate: string): number | null {
  const d = payoutDate.trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) return null
  const parsed = new Date(`${d}T12:00:00`)
  return Number.isNaN(parsed.getTime()) ? null : parsed.getTime()
}

function withdrawalMatchesDashboardPeriod(
  payoutDate: string,
  period: DashboardEquityPeriodContext
): boolean {
  const d = payoutDate.trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) return false
  const now = period.now ?? new Date()

  if (period.selectedDate.trim()) {
    const key = getTradingDayKey(`${d}T12:00:00`)
    return key === period.selectedDate.trim()
  }

  if (period.timeFilter === "all") return true

  const instant = new Date(`${d}T12:00:00`)
  if (period.timeFilter === "daily") {
    return instant.toDateString() === now.toDateString()
  }
  if (period.timeFilter === "weekly") {
    const weekAgo = new Date(now)
    weekAgo.setDate(now.getDate() - 7)
    return instant >= weekAgo
  }
  if (period.timeFilter === "monthly") {
    return (
      instant.getMonth() === now.getMonth() &&
      instant.getFullYear() === now.getFullYear()
    )
  }
  if (period.timeFilter === "yearly") {
    return instant.getFullYear() === now.getFullYear()
  }
  if (period.timeFilter === "custom") {
    if (!period.customRangeStart.trim() || !period.customRangeEnd.trim()) {
      return true
    }
    const start = new Date(`${period.customRangeStart.trim()}T00:00:00`)
    const end = new Date(`${period.customRangeEnd.trim()}T23:59:59.999`)
    return instant >= start && instant <= end
  }
  return true
}

function tradeMatchesDashboardPeriod(
  trade: DashboardTradeDateFields,
  period: DashboardEquityPeriodContext
): boolean {
  const now = period.now ?? new Date()
  if (
    period.selectedDate.trim() &&
    !tradeMatchesDashboardSelectedDate(trade, period.selectedDate)
  ) {
    return false
  }
  return tradeMatchesDashboardTimeFilter(
    trade,
    period.timeFilter,
    now,
    period.customRangeStart,
    period.customRangeEnd
  )
}

function buildLifetimeTimeline(
  accountId: string,
  lifetimeTrades: readonly ({ account_id?: unknown; pnl?: unknown } & DashboardTradeDateFields)[],
  ledgerEntries: readonly (ManualPayoutLedgerEntry & { note?: string | null })[]
): TimelineEvent[] {
  const id = String(accountId).trim()
  const events: TimelineEvent[] = []

  for (const trade of excludeBacktestTrades([...lifetimeTrades])) {
    if (String(trade.account_id ?? "").trim() !== id) continue
    const sortMs = resolveDashboardTradeDate(trade)?.getTime()
    if (sortMs == null) continue
    const date = formatDashboardEquityCurvePointDate(trade)
    if (!date) continue
    events.push({
      sortMs,
      date,
      kind: "trade",
      delta: Number(trade.pnl) || 0,
    })
  }

  for (const entry of ledgerEntries) {
    const sortMs = payoutDateToSortMs(entry.payout_date)
    if (sortMs == null) continue
    events.push({
      sortMs,
      date: new Date(sortMs).toISOString(),
      kind: "withdrawal",
      delta: -(Number(entry.amount) || 0),
      withdrawalBehavior:
        parseWithdrawalDrawdownBehaviorFromNote(entry.note) ??
        "reset_to_account",
    })
  }

  events.sort((a, b) => {
    if (a.sortMs !== b.sortMs) return a.sortMs - b.sortMs
    if (a.kind === b.kind) return 0
    return a.kind === "trade" ? -1 : 1
  })

  return events
}

type DrawdownState = {
  baseline: number
  highWaterMark: number
  trailingFloor: number
}

function applyWithdrawalDrawdownRules(
  state: DrawdownState,
  config: LivePersonalDrawdownConfig,
  equityAfterWithdrawal: number,
  behavior: LiveWithdrawalDrawdownBehavior
): DrawdownState {
  if (behavior === "reset_to_account") {
    const next = {
      baseline: equityAfterWithdrawal,
      highWaterMark: equityAfterWithdrawal,
      trailingFloor: equityAfterWithdrawal - config.limitAmount,
    }
    return next
  }

  return state
}

function floorForState(
  state: DrawdownState,
  config: LivePersonalDrawdownConfig
): number {
  if (config.limitType === "fixed") {
    return state.baseline - config.limitAmount
  }
  return state.trailingFloor
}

function applyEventToDrawdownState(
  state: DrawdownState,
  config: LivePersonalDrawdownConfig,
  equity: number,
  event: TimelineEvent
): DrawdownState {
  if (event.kind === "withdrawal") {
    return applyWithdrawalDrawdownRules(
      state,
      config,
      equity,
      event.withdrawalBehavior ?? "reset_to_account"
    )
  }
  if (config.limitType === "fixed") {
    return state
  }
  const highWaterMark = Math.max(state.highWaterMark, equity)
  const candidate = highWaterMark - config.limitAmount
  return {
    ...state,
    highWaterMark,
    trailingFloor: Math.max(state.trailingFloor, candidate),
  }
}

function replayTimelineUntil(options: {
  events: TimelineEvent[]
  startingBalance: number
  config: LivePersonalDrawdownConfig
  stopBeforeMs: number | null
}): { equity: number; state: DrawdownState } {
  const { events, startingBalance, config, stopBeforeMs } = options
  let equity = startingBalance
  let state: DrawdownState = {
    baseline: startingBalance,
    highWaterMark: startingBalance,
    trailingFloor: startingBalance - config.limitAmount,
  }

  for (const event of events) {
    if (stopBeforeMs != null && event.sortMs >= stopBeforeMs) break
    equity += event.delta
    state = applyEventToDrawdownState(state, config, equity, event)
  }

  return { equity, state }
}

/**
 * Balance equity curve + personal drawdown floor (informational).
 * Floor replay uses full account history; chart window keeps period opening balance/floor.
 */
export function computeLivePersonalDrawdownEquitySeries(options: {
  account: { account_size?: unknown }
  accountId: string
  config: LivePersonalDrawdownConfig
  lifetimeTrades: readonly ({ account_id?: unknown; pnl?: unknown } & DashboardTradeDateFields)[]
  ledgerEntries: readonly (ManualPayoutLedgerEntry & { note?: string | null })[]
  period: DashboardEquityPeriodContext
}): LivePersonalDrawdownChartPoint[] {
  const {
    account,
    accountId,
    config,
    lifetimeTrades,
    ledgerEntries,
    period,
  } = options

  const startingBalance = parseAccountSizeToNumber(account)
  const allEvents = buildLifetimeTimeline(accountId, lifetimeTrades, ledgerEntries)

  const periodStartMs = resolveDashboardPeriodStartMs(period)
  const periodEndMs = resolveDashboardPeriodEndMs(period)
  const hasPeriodWindow =
    periodStartMs != null || period.selectedDate.trim().length > 0

  if (!hasPeriodWindow) {
    const points: LivePersonalDrawdownChartPoint[] = []
    let equity = startingBalance
    let state: DrawdownState = {
      baseline: startingBalance,
      highWaterMark: startingBalance,
      trailingFloor: startingBalance - config.limitAmount,
    }

    if (allEvents.length === 0) {
      return [
        {
          date: new Date().toISOString(),
          equity: startingBalance,
          drawdownFloor: floorForState(state, config),
        },
      ]
    }

    points.push({
      date: allEvents[0].date,
      equity: startingBalance,
      drawdownFloor: floorForState(state, config),
    })

    for (const event of allEvents) {
      equity += event.delta
      state = applyEventToDrawdownState(state, config, equity, event)
      points.push({
        date: event.date,
        equity,
        drawdownFloor: floorForState(state, config),
      })
    }
    return points
  }

  const opening = replayTimelineUntil({
    events: allEvents,
    startingBalance,
    config,
    stopBeforeMs: periodStartMs ?? periodEndMs,
  })

  const cutoffMs = periodStartMs ?? periodEndMs
  const inPeriodEvents = allEvents.filter((event) => {
    if (event.sortMs < cutoffMs) return false
    if (event.kind === "trade") {
      const trade = lifetimeTrades.find(
        (t) => resolveDashboardTradeDate(t)?.getTime() === event.sortMs
      )
      return trade ? tradeMatchesDashboardPeriod(trade, period) : false
    }
    const entry = ledgerEntries.find(
      (e) => payoutDateToSortMs(e.payout_date) === event.sortMs
    )
    return entry
      ? withdrawalMatchesDashboardPeriod(entry.payout_date, period)
      : false
  })

  const anchorDate = new Date(cutoffMs).toISOString()
  const points: LivePersonalDrawdownChartPoint[] = [
    {
      date: anchorDate,
      equity: opening.equity,
      drawdownFloor: floorForState(opening.state, config),
    },
  ]

  if (inPeriodEvents.length === 0) {
    return points
  }

  let equity = opening.equity
  let state = opening.state

  for (const event of inPeriodEvents) {
    equity += event.delta
    state = applyEventToDrawdownState(state, config, equity, event)
    points.push({
      date: event.date,
      equity,
      drawdownFloor: floorForState(state, config),
    })
  }

  return points
}

export function buildLivePersonalDrawdownAccountUpdate(
  config: LivePersonalDrawdownConfig | null
): {
  max_drawdown: number | null
  drawdown_type: string | null
} {
  if (!config) {
    return { max_drawdown: null, drawdown_type: null }
  }
  return {
    max_drawdown: config.limitAmount,
    drawdown_type: livePersonalDrawdownTypeToAccountDrawdownType(
      config.limitType
    ),
  }
}
