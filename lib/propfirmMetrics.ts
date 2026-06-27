/**
 * PropFirm Mode calculation helpers.
 * Extracted from the analytics page for testability and reuse.
 *
 * ## Metric sources (Prop Firm page)
 *
 * All inputs are trades for the **selected account only** (page filters `account_id`).
 *
 * | UI metric | Scope | Source |
 * |---|---|---|
 * | Total P&L (hero) | Lifetime | `lifetimeTotalPnL` |
 * | Current balance | Post-payout cycle | `displayCurrentBalance` (cycle anchor + cycle trades) |
 * | Distance to DD | Payout cycle | `cycleTrailingMetrics.distanceToDD` |
 * | Winning days | Payout cycle | `cycleDailyMetrics.winningDays` |
 * | Equity curve | Lifetime | `buildPropfirmEquityCurveData(trades, payouts)` |
 * | Max / daily drawdown rules | Payout cycle | `cycleTrailingMetrics`, `cycleDailyMetrics.worstDailyLossUsed` |
 * | Consistency | Payout cycle | `cycleConsistencyMetrics` |
 * | Cycle P&L | Payout cycle | `cyclePnL` |
 * | Profit target % | Payout cycle | `cycleProgress.progressPercent` |
 * | Drawdown used % | Payout cycle | `cycleProgress.ddPercent` |
 * | Account status | Payout cycle | `cycleProgress.status` |
 * | Today P&L | Calendar day | EST trading-day bucket from all trades (`lifetimeDailyMetrics.todayPnL`) |
 * | Daily performance list | Lifetime | All prop-firm trading days (`lifetimeDailyMetrics.dailyRows`) |
 *
 * Payout cycle boundaries come from `account_payout_cycles` (see `propfirmPayoutCycles.ts`).
 * Before the first recorded payout, the implicit cycle starts at `accounts.account_size`.
 */

import { getTradingDayKey } from "./formatDate.ts"

export type PropfirmTrade = {
  id?: string | null
  pnl?: number | string | null
  date?: string | null
  trade_date?: string | null
  entry_time?: string | null
  created_at?: string | null
}

export type PropfirmAccountRules = {
  account_size?: unknown
  consistency?: number | string | null
  max_drawdown?: number | string | null
  profit_target?: number | string | null
}

export type TrailingDrawdownResult = {
  currentBalance: number
  peakBalance: number
  drawdownFloor: number
  distanceToDD: number
  /** Largest (peak - balance) observed after any trade (for "max DD used" vs limit). */
  maxDrawdownUsed: number
  /** True if at any point after a trade, balance fell below the trailing drawdown floor. */
  breachedTrailingDD: boolean
}

export type ConsistencyRuleResult = {
  biggestWin: number
  totalProfit: number
  allowedMax: number
  isConsistent: boolean
  ruleActive: boolean
}

export type DailyMetricsResult = {
  dailyPnLMap: Record<string, number>
  dailyRows: [string, number][]
  winningDays: number
  todayPnL: number
  worstDay: number
  worstDailyLossUsed: number
}

export type PropfirmProgressResult = {
  totalPnL: number
  progressPercent: number
  isPassed: boolean
  isFailed: boolean
  status: "PASSED" | "FAILED" | "IN PROGRESS"
  ddPercent: number
  distanceDanger: boolean
}

export type PayoutDrawdownBehavior = "reset_to_account" | "keep_trailing"

export type PropfirmPayoutCycleContext = {
  /** ISO timestamp when the current payout cycle began; null = account inception. */
  startedAt: string | null
  /** Account balance at the start of the current payout cycle. */
  cycleStartBalance: number
  /** Trailing drawdown floor in effect at cycle start (after payout). */
  initialDrawdownFloor?: number | null
  drawdownBehavior?: PayoutDrawdownBehavior | null
  cycleNumber?: number | null
}

export type TrailingDrawdownOptions = {
  /** Prop firm account base (cap for trailing floor). Defaults to startingBalance. */
  accountBaseBalance?: number
  /** Fixed floor at cycle start (e.g. after payout). */
  initialDrawdownFloor?: number | null
  /** When true, floor stays at the initial value (reset drawdown after payout). */
  lockDrawdownFloor?: boolean
}

export type PropfirmAccountMetricsResult = {
  startingBalance: number
  /** Payout-cycle daily aggregation (winning days, daily drawdown rule). */
  cycleDailyMetrics: DailyMetricsResult
  /** Payout-cycle trailing drawdown (remaining drawdown, max DD used). */
  cycleTrailingMetrics: TrailingDrawdownResult
  /** Payout-cycle consistency rule. */
  cycleConsistencyMetrics: ConsistencyRuleResult
  /** Payout-cycle progress (profit target, status, drawdown bars). */
  cycleProgress: PropfirmProgressResult
  /** Lifetime net P&L across all trades. */
  lifetimeTotalPnL: number
  /** Profit since the current payout cycle start balance. */
  cyclePnL: number
  /** Lifetime daily aggregation (daily list, today P&L). */
  lifetimeDailyMetrics: DailyMetricsResult
  /** Lifetime trailing drawdown (trade-simulated, unchanged by withdrawals). */
  lifetimeTrailingMetrics: TrailingDrawdownResult
  /** Balance shown in UI: cycle anchor + cycle trades when a payout cycle is active. */
  displayCurrentBalance: number
  payoutCycle: PropfirmPayoutCycleContext
}

export type PropfirmEquityCurvePoint = {
  date: string
  balance: number
  pnl: number
}

/** Future UI toggle: lifetime vs current payout cycle equity curve. */
export type PropfirmEquityCurveScope = "lifetime" | "cycle"

export type PropfirmEquityPayoutEventInput = {
  endedAt: string
  amount: number
}

export type PropfirmEquityEvent =
  | {
      kind: "trade"
      sortMs: number
      label: string
      delta: number
    }
  | {
      kind: "payout"
      sortMs: number
      label: string
      amount: number
    }

function equityEventLabelFromIsoTimestamp(isoTimestamp: string): string {
  const parsed = new Date(isoTimestamp)
  if (!Number.isNaN(parsed.getTime())) {
    return getTradingDayKey(parsed.toISOString())
  }
  return isoTimestamp.trim().slice(0, 10)
}

/** Build a chronological trade + payout timeline for equity replay. */
export function buildPropfirmEquityEvents(
  trades: PropfirmTrade[],
  payouts: PropfirmEquityPayoutEventInput[] = []
): PropfirmEquityEvent[] {
  const events: PropfirmEquityEvent[] = []

  for (const trade of sortTradesByTradeSequence(dedupeTradesById(trades))) {
    const sortMs = getPropfirmTradeEpochMs(trade)
    const label = getPropfirmTradingDay(trade)
    if (sortMs == null || !label) continue

    events.push({
      kind: "trade",
      sortMs,
      label,
      delta: Number(trade.pnl || 0),
    })
  }

  for (const payout of payouts) {
    const endedAt = String(payout.endedAt ?? "").trim()
    const amount = Number(payout.amount)
    if (!endedAt || !Number.isFinite(amount) || amount <= 0) continue

    const sortMs = new Date(endedAt).getTime()
    if (!Number.isFinite(sortMs)) continue

    events.push({
      kind: "payout",
      sortMs,
      label: equityEventLabelFromIsoTimestamp(endedAt),
      amount,
    })
  }

  return events.sort((left, right) => {
    if (left.sortMs !== right.sortMs) return left.sortMs - right.sortMs
    if (left.kind === right.kind) return 0
    return left.kind === "trade" ? -1 : 1
  })
}

function dedupePropfirmEquityCurvePoints(
  points: PropfirmEquityCurvePoint[]
): PropfirmEquityCurvePoint[] {
  return points.filter((point, index) => {
    if (index === 0) return true
    const previous = points[index - 1]
    return !(
      previous.date === point.date &&
      previous.balance === point.balance &&
      previous.pnl === point.pnl
    )
  })
}

/** Replay trade and payout events into plotted equity curve points. */
export function replayPropfirmEquityEvents(
  startingBalance: number,
  events: PropfirmEquityEvent[]
): PropfirmEquityCurvePoint[] {
  if (startingBalance <= 0) return []

  let balance = startingBalance
  const points: PropfirmEquityCurvePoint[] = [{ date: "Start", balance, pnl: 0 }]

  for (const event of events) {
    if (event.kind === "trade") {
      balance += event.delta
      points.push({ date: event.label, balance, pnl: event.delta })
      continue
    }

    balance -= event.amount
    points.push({ date: event.label, balance, pnl: -event.amount })
  }

  return dedupePropfirmEquityCurvePoints(points)
}

export function buildPropfirmEquityCurveData(
  trades: PropfirmTrade[],
  startingBalance: number,
  payouts: PropfirmEquityPayoutEventInput[] = []
): PropfirmEquityCurvePoint[] {
  return replayPropfirmEquityEvents(
    startingBalance,
    buildPropfirmEquityEvents(trades, payouts)
  )
}

export function selectPropfirmEquityCurveInputs(
  metrics: PropfirmAccountMetricsResult,
  scope: PropfirmEquityCurveScope = "lifetime"
): {
  startingBalance: number
  expectedEndingBalance: number
} {
  if (scope === "cycle") {
    return {
      startingBalance: metrics.payoutCycle.cycleStartBalance,
      expectedEndingBalance: metrics.displayCurrentBalance,
    }
  }

  return {
    startingBalance: metrics.startingBalance,
    expectedEndingBalance: metrics.displayCurrentBalance,
  }
}

const EMPTY_TRAILING_DRAWDOWN: TrailingDrawdownResult = {
  currentBalance: 0,
  peakBalance: 0,
  drawdownFloor: 0,
  distanceToDD: 0,
  maxDrawdownUsed: 0,
  breachedTrailingDD: false,
}

const INACTIVE_CONSISTENCY_RULE: ConsistencyRuleResult = {
  biggestWin: 0,
  totalProfit: 0,
  allowedMax: 0,
  isConsistent: true,
  ruleActive: false,
}

function addCalendarDay(dateKey: string): string | null {
  const [year, month, day] = dateKey.split("-").map(Number)
  if (![year, month, day].every(Number.isFinite)) return null
  const d = new Date(Date.UTC(year, month - 1, day + 1))
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(
    2,
    "0"
  )}-${String(d.getUTCDate()).padStart(2, "0")}`
}

function resolvePropfirmTradingTimeSource(trade: {
  date?: string | null
  trade_date?: string | null
  entry_time?: string | null
}): string | null {
  const tradeDate = String(trade.trade_date ?? trade.date ?? "")
    .trim()
    .slice(0, 10)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(tradeDate)) return null

  const entryTime = String(trade.entry_time ?? "").trim()
  if (!entryTime) return tradeDate

  const parsedEntry = new Date(entryTime)
  if (!Number.isNaN(parsedEntry.getTime())) return entryTime

  const timeOnly = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(entryTime)
  if (!timeOnly) return tradeDate

  const hour = Number(timeOnly[1])
  if (!Number.isFinite(hour)) return tradeDate

  return hour >= 18 ? addCalendarDay(tradeDate) : tradeDate
}

/** Futures-style session day key using trade_date/entry_time, never import created_at. */
export function getPropfirmTradingDay(trade: {
  date?: string | null
  trade_date?: string | null
  entry_time?: string | null
}): string | null {
  const source = resolvePropfirmTradingTimeSource(trade)
  if (!source) return null
  return getTradingDayKey(source)
}

/** Parse `accounts.account_size` (number or strings like "50K", "50,000") to dollars. */
export function parseAccountSizeToNumber(account: {
  account_size?: unknown
}): number {
  const raw = account?.account_size
  if (raw == null || raw === "") return 0
  if (typeof raw === "number" && Number.isFinite(raw)) return raw
  const s = String(raw).trim().replace(/,/g, "")
  const k = /^([\d.]+)\s*k$/i.exec(s)
  if (k) {
    const n = Number(k[1])
    return Number.isFinite(n) ? n * 1000 : 0
  }
  const n = Number(s)
  return Number.isFinite(n) ? n : 0
}

export function formatPropfirmUsd(n: number): string {
  const sign = n < 0 ? "-" : ""
  return `${sign}$${Math.abs(n).toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  })}`
}

export const PROPFIRM_EQUITY_CURVE_PADDING = 500
export const PROPFIRM_EQUITY_CURVE_MIN_RANGE = 1000
export const PROPFIRM_EQUITY_CURVE_SMALL_MOVEMENT = 500

export type PropfirmEquityCurveYDomainOptions = {
  /** Optional reference-line Y values to keep visible (profit target, drawdown floor, etc.). */
  includeValues?: number[]
}

/**
 * Y-axis domain for the prop firm equity curve: zooms around plotted balances
 * with $500 padding and a $1,000 minimum visible range when movement is tight.
 * Pass `includeValues` only when optional reference lines must stay in view.
 */
export function computePropfirmEquityCurveYDomain(
  values: number[],
  options?: PropfirmEquityCurveYDomainOptions
): [number, number] | undefined {
  const includeValues = options?.includeValues ?? []
  const allValues = [...values, ...includeValues].filter((v) =>
    Number.isFinite(v)
  )
  if (allValues.length === 0) return undefined

  const minValue = Math.min(...allValues)
  const maxValue = Math.max(...allValues)
  const movement = maxValue - minValue

  if (movement < PROPFIRM_EQUITY_CURVE_SMALL_MOVEMENT) {
    const mid = (minValue + maxValue) / 2
    return [
      mid - PROPFIRM_EQUITY_CURVE_MIN_RANGE / 2,
      mid + PROPFIRM_EQUITY_CURVE_MIN_RANGE / 2,
    ]
  }

  let lowerBound = minValue - PROPFIRM_EQUITY_CURVE_PADDING
  let upperBound = maxValue + PROPFIRM_EQUITY_CURVE_PADDING

  if (upperBound - lowerBound < PROPFIRM_EQUITY_CURVE_MIN_RANGE) {
    const mid = (minValue + maxValue) / 2
    lowerBound = mid - PROPFIRM_EQUITY_CURVE_MIN_RANGE / 2
    upperBound = mid + PROPFIRM_EQUITY_CURVE_MIN_RANGE / 2
  }

  return [lowerBound, upperBound]
}

const PROPFIRM_EQUITY_CURVE_NICE_STEPS = [
  500, 1000, 2500, 5000, 10000, 25000, 50000,
] as const

/** Rounded Y-axis ticks for the prop firm equity curve. */
export function computePropfirmEquityCurveYTicks(
  domain: [number, number] | undefined,
  maxTicks = 6
): number[] | undefined {
  if (!domain) return undefined

  const [min, max] = domain
  const range = max - min
  if (range <= 0) return [Math.round(min)]

  let step: number =
    PROPFIRM_EQUITY_CURVE_NICE_STEPS[
      PROPFIRM_EQUITY_CURVE_NICE_STEPS.length - 1
    ]
  for (const candidate of PROPFIRM_EQUITY_CURVE_NICE_STEPS) {
    if (range / candidate <= maxTicks) {
      step = candidate
      break
    }
  }

  const start = Math.floor(min / step) * step
  const end = Math.ceil(max / step) * step
  const ticks: number[] = []
  for (let value = start; value <= end + step * 0.001; value += step) {
    ticks.push(Math.round(value))
  }

  return ticks.length > 0 ? ticks : [Math.round(min), Math.round(max)]
}

/** Drop duplicate trade rows (same `id`) so PnL is not double-counted. */
export function dedupeTradesById<T extends PropfirmTrade>(trades: T[]): T[] {
  const seen = new Set<string>()
  const out: T[] = []
  for (const t of trades) {
    const id = t?.id
    if (id != null && id !== "") {
      const key = String(id)
      if (seen.has(key)) continue
      seen.add(key)
    }
    out.push(t)
  }
  return out
}

/** Display / daily aggregation order (trade_date, then entry_time). */
export function sortTradesByTradeSequence<T extends PropfirmTrade>(trades: T[]): T[] {
  return [...trades].sort((a, b) => {
    const da = String(a.trade_date ?? a.date ?? "")
    const db = String(b.trade_date ?? b.date ?? "")
    const byDate = da.localeCompare(db)
    if (byDate !== 0) return byDate
    const at = a.entry_time ? new Date(a.entry_time).getTime() : 0
    const bt = b.entry_time ? new Date(b.entry_time).getTime() : 0
    return at - bt
  })
}

/** Trailing drawdown simulation order (legacy: created_at ascending). */
export function sortTradesByCreatedAt<T extends PropfirmTrade>(trades: T[]): T[] {
  return [...trades].sort(
    (a, b) => +new Date(a.created_at ?? 0) - +new Date(b.created_at ?? 0)
  )
}

/**
 * Trailing drawdown: floor rises with equity until it reaches the starting
 * balance. Once capped at the account size, it never trails higher.
 */
/** Drawdown floor after a payout, based on prop firm reset vs trailing rules. */
export function computePayoutDrawdownFloor(
  behavior: PayoutDrawdownBehavior,
  accountBaseBalance: number,
  trailingMetricsBeforePayout: TrailingDrawdownResult,
  maxDrawdown: number
): number {
  if (behavior === "reset_to_account") {
    return accountBaseBalance
  }

  const previousFloor = trailingMetricsBeforePayout.drawdownFloor
  if (Number.isFinite(previousFloor)) {
    return previousFloor
  }

  const maxDd = Number(maxDrawdown) || 0
  const balanceBefore = trailingMetricsBeforePayout.currentBalance
  return Math.min(accountBaseBalance, balanceBefore - maxDd)
}

export function computeTrailingDrawdown(
  trades: PropfirmTrade[],
  startingBalance: number,
  maxDrawdown: number,
  options?: TrailingDrawdownOptions
): TrailingDrawdownResult {
  const maxDd = Number(maxDrawdown) || 0
  const accountBase = options?.accountBaseBalance ?? startingBalance

  const uniqueTrades = dedupeTradesById(trades)
  const tradesSorted = sortTradesByCreatedAt(uniqueTrades)

  let balance = startingBalance
  let peakBalance = startingBalance
  const initialFloor = options?.initialDrawdownFloor
  let drawdownFloor =
    initialFloor != null && Number.isFinite(initialFloor)
      ? initialFloor
      : startingBalance - maxDd
  let maxDrawdownUsed = 0
  let breachedTrailingDD = false

  for (const trade of tradesSorted) {
    const pnl = parseFloat(String(trade.pnl ?? "")) || 0

    balance += pnl

    if (balance > peakBalance) {
      peakBalance = balance
      if (!options?.lockDrawdownFloor) {
        drawdownFloor = Math.min(accountBase, peakBalance - maxDd)
      }
    }

    const drawdownUsed = Math.max(0, drawdownFloor + maxDd - balance)
    if (drawdownUsed > maxDrawdownUsed) {
      maxDrawdownUsed = drawdownUsed
    }

    if (maxDd > 0 && balance < drawdownFloor) {
      breachedTrailingDD = true
    }
  }

  const distanceToDD = balance - drawdownFloor

  return {
    currentBalance: balance,
    peakBalance,
    drawdownFloor,
    distanceToDD,
    maxDrawdownUsed,
    breachedTrailingDD,
  }
}

/** `consistency_percent` from account rules (DB column `consistency`). */
export function computeConsistencyRule(
  trades: PropfirmTrade[],
  consistencyPercent: number
): ConsistencyRuleResult {
  const pct = Number(consistencyPercent)
  const ruleActive = Number.isFinite(pct) && pct > 0

  const winningTrades = trades.filter((t) => Number(t.pnl) > 0)
  const totalProfit = winningTrades.reduce(
    (sum, t) => sum + Number(t.pnl || 0),
    0
  )
  const biggestWin =
    winningTrades.length > 0
      ? Math.max(...winningTrades.map((t) => Number(t.pnl || 0)))
      : 0

  const allowedMax = ruleActive ? totalProfit * (pct / 100) : 0
  const isConsistent = !ruleActive || biggestWin <= allowedMax

  return {
    biggestWin,
    totalProfit,
    allowedMax,
    isConsistent,
    ruleActive,
  }
}

export function computeTotalPnL(trades: PropfirmTrade[]): number {
  return sortTradesByTradeSequence(trades).reduce(
    (sum, t) => sum + Number(t.pnl || 0),
    0
  )
}

export function getEstCalendarDayKey(date: Date = new Date()): string {
  const nowEST = new Date(
    date.toLocaleString("en-US", {
      timeZone: "America/New_York",
    })
  )
  return `${nowEST.getFullYear()}-${String(nowEST.getMonth() + 1).padStart(
    2,
    "0"
  )}-${String(nowEST.getDate()).padStart(2, "0")}`
}

export function buildDailyPnLMap(
  trades: PropfirmTrade[]
): Record<string, number> {
  const dailyPnLMap: Record<string, number> = {}

  sortTradesByTradeSequence(trades).forEach((t) => {
    const day = getPropfirmTradingDay(t)
    if (!day) return
    dailyPnLMap[day] = (dailyPnLMap[day] || 0) + Number(t.pnl || 0)
  })

  return dailyPnLMap
}

export function computeDailyMetrics(
  trades: PropfirmTrade[],
  now: Date = new Date()
): DailyMetricsResult {
  const dailyPnLMap = buildDailyPnLMap(trades)
  const dailyRows = Object.entries(dailyPnLMap).sort(([a], [b]) =>
    a.localeCompare(b)
  )
  const winningDays = Object.values(dailyPnLMap).filter((pnl) => pnl > 0).length
  const todayKey = getEstCalendarDayKey(now)
  const todayPnL = dailyPnLMap[todayKey] || 0
  const dayPnLValues = Object.values(dailyPnLMap)
  const worstDay = dayPnLValues.length > 0 ? Math.min(...dayPnLValues) : 0
  const worstDailyLossUsed = worstDay < 0 ? Math.abs(worstDay) : 0

  return {
    dailyPnLMap,
    dailyRows,
    winningDays,
    todayPnL,
    worstDay,
    worstDailyLossUsed,
  }
}

/** Resolve a trade to epoch ms for payout-cycle cutoff comparisons. */
export function getPropfirmTradeEpochMs(trade: PropfirmTrade): number | null {
  const tradeDate = String(trade.trade_date ?? trade.date ?? "")
    .trim()
    .slice(0, 10)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(tradeDate)) return null

  const entryTime = String(trade.entry_time ?? "").trim()
  if (entryTime) {
    const parsedEntry = new Date(entryTime)
    if (!Number.isNaN(parsedEntry.getTime())) return parsedEntry.getTime()
  }

  return new Date(`${tradeDate}T12:00:00Z`).getTime()
}

/** Trades at or after the payout cycle start timestamp (immediate reset on Record Payout). */
export function filterTradesForPayoutCycle<T extends PropfirmTrade>(
  trades: T[],
  cycleStartedAt: string | null
): T[] {
  if (!cycleStartedAt) return trades

  const cutoffMs = new Date(cycleStartedAt).getTime()
  if (!Number.isFinite(cutoffMs)) return trades

  return trades.filter((trade) => {
    const tradeMs = getPropfirmTradeEpochMs(trade)
    return tradeMs != null && tradeMs >= cutoffMs
  })
}

export function computeCyclePnL(
  cycleCurrentBalance: number,
  cycleStartBalance: number
): number {
  return cycleCurrentBalance - cycleStartBalance
}

export function computePropfirmProgress(
  cyclePnL: number,
  trailingMetrics: TrailingDrawdownResult,
  account: PropfirmAccountRules | null
): PropfirmProgressResult {
  const profitTarget = Number(account?.profit_target) || 0
  const maxDdLimit = Number(account?.max_drawdown) || 0
  const drawdownUsed = trailingMetrics.maxDrawdownUsed

  const progressPercent = profitTarget
    ? Math.min((cyclePnL / profitTarget) * 100, 100)
    : 0

  const isPassed = !!account && profitTarget > 0 && cyclePnL >= profitTarget
  const isFailed =
    !!account &&
    maxDdLimit > 0 &&
    (trailingMetrics.breachedTrailingDD || trailingMetrics.distanceToDD < 0)

  const status: PropfirmProgressResult["status"] = isFailed
    ? "FAILED"
    : isPassed
      ? "PASSED"
      : "IN PROGRESS"

  const ddPercent =
    maxDdLimit > 0 ? Math.min((drawdownUsed / maxDdLimit) * 100, 100) : 0

  const distanceToDD = trailingMetrics.distanceToDD
  const distanceDanger =
    maxDdLimit > 0 &&
    distanceToDD >= 0 &&
    distanceToDD < 0.2 * maxDdLimit

  return {
    totalPnL: cyclePnL,
    progressPercent,
    isPassed,
    isFailed,
    status,
    ddPercent,
    distanceDanger,
  }
}

export function computePropfirmAccountMetrics(
  trades: PropfirmTrade[],
  account: PropfirmAccountRules | null,
  payoutCycle?: PropfirmPayoutCycleContext | null
): PropfirmAccountMetricsResult {
  const startingBalance = account ? parseAccountSizeToNumber(account) : 0
  const cycleContext: PropfirmPayoutCycleContext = payoutCycle ?? {
    startedAt: null,
    cycleStartBalance: startingBalance,
  }

  const uniqueTrades = dedupeTradesById(trades)
  const lifetimeDailyMetrics = computeDailyMetrics(uniqueTrades)
  const totalPnL = computeTotalPnL(uniqueTrades)

  const lifetimeTrailingMetrics = account
    ? computeTrailingDrawdown(
        uniqueTrades,
        startingBalance,
        Number(account.max_drawdown) || 0
      )
    : EMPTY_TRAILING_DRAWDOWN

  const cycleTrades = filterTradesForPayoutCycle(
    uniqueTrades,
    cycleContext.startedAt
  )
  const cycleDailyMetrics = computeDailyMetrics(cycleTrades)
  const trailingOptions: TrailingDrawdownOptions | undefined = account
    ? {
        accountBaseBalance: startingBalance,
        initialDrawdownFloor: cycleContext.initialDrawdownFloor,
        lockDrawdownFloor:
          cycleContext.drawdownBehavior === "reset_to_account" &&
          cycleContext.initialDrawdownFloor != null,
      }
    : undefined
  const cycleTrailingMetrics = account
    ? computeTrailingDrawdown(
        cycleTrades,
        cycleContext.cycleStartBalance,
        Number(account.max_drawdown) || 0,
        trailingOptions
      )
    : EMPTY_TRAILING_DRAWDOWN
  const cycleConsistencyMetrics = account
    ? computeConsistencyRule(cycleTrades, Number(account.consistency) || 0)
    : INACTIVE_CONSISTENCY_RULE

  const displayCurrentBalance = cycleContext.startedAt
    ? cycleTrailingMetrics.currentBalance
    : lifetimeTrailingMetrics.currentBalance

  const cyclePnL = computeCyclePnL(
    cycleTrailingMetrics.currentBalance,
    cycleContext.cycleStartBalance
  )
  const cycleProgress = computePropfirmProgress(
    cyclePnL,
    cycleTrailingMetrics,
    account
  )

  return {
    startingBalance,
    cycleDailyMetrics,
    cycleTrailingMetrics,
    cycleConsistencyMetrics,
    cycleProgress,
    lifetimeTotalPnL: totalPnL,
    cyclePnL,
    lifetimeDailyMetrics,
    lifetimeTrailingMetrics,
    displayCurrentBalance,
    payoutCycle: cycleContext,
  }
}
