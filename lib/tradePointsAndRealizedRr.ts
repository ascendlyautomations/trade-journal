import {
  calculateDirectionalPoints,
  hasStoredTradePoints,
  type TradePointsSource,
} from "./resolveTradePoints.ts"
import { hasStoredRr, parseOptionalRr } from "./tradeRr.ts"

export type TradeRealizedRrSource = TradePointsSource & {
  rr?: unknown
  realized_rr?: unknown
  pnl?: unknown
  import_source?: string | null
  broker_connection_id?: string | null
}

/** Beyond this, treat stored/computed R as bad data for analytics (not a hard UI cap). */
export const REALIZED_RR_ANALYTICS_ABS_MAX = 25

export function isPlausibleRealizedRr(value: number): boolean {
  return Number.isFinite(value) && Math.abs(value) <= REALIZED_RR_ANALYTICS_ABS_MAX
}

/** Legacy rows often store actual net points in `points`, not plan “points targeted”. */
export function storedPointsMatchPriceActualMove(
  trade: TradePointsSource
): boolean {
  const points = parsePositivePointsTarget(trade.points)
  const actual = actualPointsFromPrices(trade)
  if (points == null || actual == null) return false
  const scale = Math.max(Math.abs(points), Math.abs(actual), 1e-6)
  return Math.abs(actual - points) / scale <= 0.25
}

/** Plan target points vs price move in incompatible units (e.g. target `1` vs index move `126`). */
export function planPointsInconsistentWithPriceMove(
  trade: TradePointsSource
): boolean {
  const points = parsePositivePointsTarget(trade.points)
  const actual = actualPointsFromPrices(trade)
  if (points == null || actual == null) return false
  if (Math.abs(actual) < 1e-6) return false
  return Math.abs(actual) / points > 10
}

export function parsePositivePointsTarget(raw: unknown): number | null {
  if (!hasStoredTradePoints(raw)) return null
  const n = Number(raw)
  if (!Number.isFinite(n) || n <= 0) return null
  return n
}

export function parsePositiveTargetedRr(raw: unknown): number | null {
  const n = parseOptionalRr(raw)
  if (n == null || n <= 0) return null
  return n
}

export function parseNonnegativeMaxRrReached(raw: unknown): number | null {
  const n = parseOptionalRr(raw)
  if (n == null || n < 0) return null
  return n
}

export function actualPointsFromPrices(
  trade: TradePointsSource
): number | null {
  const entry = Number(trade.entry_price)
  const exit = Number(trade.exit_price)
  if (!Number.isFinite(entry) || !Number.isFinite(exit)) return null
  const direction =
    trade.direction != null ? String(trade.direction) : "Long"
  return calculateDirectionalPoints(direction, entry, exit)
}

/** Realized R:R from prices + plan fields (does not read stored realized_rr). */
export function computeRealizedRrFromPricesAndPlan(
  trade: TradeRealizedRrSource
): number | null {
  const pointsTargeted = parsePositivePointsTarget(trade.points)
  const targetedRr = parsePositiveTargetedRr(trade.rr)
  if (pointsTargeted == null || targetedRr == null) return null
  if (storedPointsMatchPriceActualMove(trade)) return null
  if (planPointsInconsistentWithPriceMove(trade)) return null
  const actual = actualPointsFromPrices(trade)
  if (actual == null) return null
  const realized = (actual * targetedRr) / pointsTargeted
  return isPlausibleRealizedRr(realized) ? realized : null
}

/**
 * Authoritative realized R:R for display/analytics.
 * Never substitutes targeted R:R for manual trades.
 */
export function resolveRealizedRr(
  trade: TradeRealizedRrSource | null | undefined
): number | null {
  if (!trade) return null
  if (hasStoredRr(trade.realized_rr)) {
    const stored = Number(trade.realized_rr)
    if (isPlausibleRealizedRr(stored)) return stored
  }
  if (storedPointsMatchPriceActualMove(trade)) {
    const legacy = legacyStoredRrAsRealized(trade)
    if (legacy != null) return legacy
  }
  const fromPlan = computeRealizedRrFromPricesAndPlan(trade)
  if (fromPlan != null) return fromPlan
  if (isAutomaticOrLegacyImportTrade(trade)) {
    return legacyStoredRrAsRealized(trade)
  }
  return null
}

export function computeActualPoints(
  trade: TradeRealizedRrSource | null | undefined
): number | null {
  if (!trade) return null
  const pointsTargeted = parsePositivePointsTarget(trade.points)
  const targetedRr = parsePositiveTargetedRr(trade.rr)
  const realizedRr = resolveRealizedRr(trade)
  if (
    pointsTargeted == null ||
    targetedRr == null ||
    realizedRr == null
  ) {
    return null
  }
  return (pointsTargeted / targetedRr) * realizedRr
}

export function formatSignedPoints(value: number | null, empty = "—"): string {
  if (value == null || !Number.isFinite(value)) return empty
  const abs = Math.abs(value)
  const formatted = abs.toLocaleString(undefined, {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })
  if (value > 0) return `+${formatted}`
  if (value < 0) return `-${formatted}`
  return "0"
}

export function isAutomaticOrLegacyImportTrade(
  trade: Pick<
    TradeRealizedRrSource,
    "import_source" | "broker_connection_id"
  >
): boolean {
  if (trade.broker_connection_id) return true
  const src = trade.import_source?.trim().toLowerCase()
  if (!src) return false
  return src !== "manual"
}

function legacyStoredRrAsRealized(
  trade: TradeRealizedRrSource
): number | null {
  if (!hasStoredRr(trade.rr)) return null
  const legacy = Number(trade.rr)
  return isPlausibleRealizedRr(legacy) ? legacy : null
}

export type ManualTradeRiskFieldValidation = {
  ok: boolean
  pointsTarget?: string
  targetedRr?: string
  maxRrReached?: string
}

/** Manual Add/Edit only — broker/CSV paths skip this. */
export function validateManualTradeRiskFields(args: {
  pnl: number
  pointsRaw: unknown
  targetedRrRaw: unknown
  maxRrReachedRaw: unknown
}): ManualTradeRiskFieldValidation {
  const errors: ManualTradeRiskFieldValidation = { ok: true }
  const pnl = args.pnl
  const requireMaxRr = !Number.isFinite(pnl) || pnl <= 0

  if (parsePositivePointsTarget(args.pointsRaw) == null) {
    errors.pointsTarget = "Points Targeted is required (positive number)."
    errors.ok = false
  }
  if (parsePositiveTargetedRr(args.targetedRrRaw) == null) {
    errors.targetedRr = "Targeted Risk/Reward is required (positive number)."
    errors.ok = false
  }
  if (requireMaxRr && parseNonnegativeMaxRrReached(args.maxRrReachedRaw) == null) {
    errors.maxRrReached =
      "Max R:R Reached is required for breakeven and losing trades (0 or greater)."
    errors.ok = false
  } else if (
    !requireMaxRr &&
    args.maxRrReachedRaw != null &&
    String(args.maxRrReachedRaw).trim() !== "" &&
    parseNonnegativeMaxRrReached(args.maxRrReachedRaw) == null
  ) {
    errors.maxRrReached = "Enter a valid Max R:R Reached (0 or greater)."
    errors.ok = false
  }

  return errors
}

export function realizedRrForManualTradeSave(
  trade: TradeRealizedRrSource & {
    direction?: unknown
    entry_price?: unknown
    exit_price?: unknown
  }
): number | null {
  return computeRealizedRrFromPricesAndPlan(trade)
}

/** Dashboard Avg R:R — realized multiples only. */
export function averageRealizedRrFromTrades(
  trades: TradeRealizedRrSource[]
): number | null {
  let sum = 0
  let count = 0
  for (const trade of trades) {
    const rr = resolveRealizedRr(trade)
    if (rr == null) continue
    sum += rr
    count += 1
  }
  return count > 0 ? sum / count : null
}
