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

export const REALIZED_RR_CANNOT_EXCEED_TARGETED =
  "Realized R:R cannot exceed Targeted R:R."

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

function parseFiniteTradePrice(raw: unknown): number | null {
  if (raw === null || raw === undefined) return null
  if (typeof raw === "string" && raw.trim() === "") return null
  const n = Number(raw)
  return Number.isFinite(n) ? n : null
}

export function actualPointsFromPrices(
  trade: TradePointsSource
): number | null {
  const entry = parseFiniteTradePrice(trade.entry_price)
  const exit = parseFiniteTradePrice(trade.exit_price)
  if (entry == null || exit == null) return null
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
  exitRr?: string
  outcomeMode?: string
  realizedRr?: string
}

export type ManualTradeSaveSource = TradeRealizedRrSource & {
  full_tp?: boolean | null
  early_exit?: boolean | null
  exit_rr?: unknown
  pnl?: unknown
  direction?: unknown
  entry_price?: unknown
  exit_price?: unknown
}

/** Winning manual saves — realized must not exceed targeted (Full TP sets equality). */
export function validateRealizedRrAgainstTargeted(
  trade: ManualTradeSaveSource
): string | null {
  const pnl = Number(trade.pnl)
  if (!Number.isFinite(pnl) || pnl <= 0) return null
  const targeted = parsePositiveTargetedRr(trade.rr)
  if (targeted == null) return null
  if (trade.full_tp === true) return null
  const realized = realizedRrForManualTradeSave(trade)
  if (realized == null) return null
  if (realized > targeted) return REALIZED_RR_CANNOT_EXCEED_TARGETED
  return null
}

export function canComputeRealizedRrFromPricesAndPlan(
  trade: TradeRealizedRrSource
): boolean {
  return computeRealizedRrFromPricesAndPlan(trade) != null
}

/** Manual Add/Edit only — broker/CSV paths skip this. */
export function validateManualTradeRiskFields(args: {
  pnl: number
  pointsRaw: unknown
  targetedRrRaw: unknown
  maxRrReachedRaw: unknown
  fullTp?: boolean
  earlyExit?: boolean
  exitRrRaw?: unknown
  entryPriceRaw?: unknown
  exitPriceRaw?: unknown
  direction?: unknown
}): ManualTradeRiskFieldValidation {
  const errors: ManualTradeRiskFieldValidation = { ok: true }
  const pnl = args.pnl
  const earlyExit = args.earlyExit === true
  const fullTp = args.fullTp === true
  const requireMaxRr = !Number.isFinite(pnl) || pnl <= 0 || earlyExit

  if (fullTp && earlyExit) {
    errors.outcomeMode = "Choose Full TP or Early Exit, not both."
    errors.ok = false
  }

  if (parsePositivePointsTarget(args.pointsRaw) == null) {
    errors.pointsTarget = "Points Targeted is required (positive number)."
    errors.ok = false
  }
  if (parsePositiveTargetedRr(args.targetedRrRaw) == null) {
    errors.targetedRr = "Targeted Risk/Reward is required (positive number)."
    errors.ok = false
  }
  if (requireMaxRr && parseNonnegativeMaxRrReached(args.maxRrReachedRaw) == null) {
    errors.maxRrReached = earlyExit
      ? "Max R:R Reached is required for early exits (0 or greater)."
      : "Max R:R Reached is required for breakeven and losing trades (0 or greater)."
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

  if (earlyExit && Number.isFinite(pnl) && pnl > 0) {
    const canCompute = canComputeRealizedRrFromPricesAndPlan({
      points: args.pointsRaw,
      rr: args.targetedRrRaw,
      entry_price: args.entryPriceRaw,
      exit_price: args.exitPriceRaw,
      direction: args.direction,
    })
    if (!canCompute) {
      const raw = args.exitRrRaw
      const trimmed = raw == null ? "" : String(raw).trim()
      if (trimmed === "") {
        errors.exitRr =
          "Exit R:R is required when entry and exit prices cannot derive it."
        errors.ok = false
      } else {
        const parsed = parseOptionalRr(raw)
        if (parsed == null || !isPlausibleRealizedRr(parsed)) {
          errors.exitRr = "Enter a valid Exit R:R."
          errors.ok = false
        } else {
          const targeted = parsePositiveTargetedRr(args.targetedRrRaw)
          if (targeted != null && parsed > targeted) {
            errors.exitRr = REALIZED_RR_CANNOT_EXCEED_TARGETED
            errors.ok = false
          }
        }
      }
    }
  }

  const saveSource: ManualTradeSaveSource = {
    points: args.pointsRaw,
    rr: args.targetedRrRaw,
    pnl,
    full_tp: fullTp,
    early_exit: earlyExit,
    exit_rr: args.exitRrRaw,
    entry_price: args.entryPriceRaw,
    exit_price: args.exitPriceRaw,
    direction: args.direction,
  }
  if (!errors.exitRr) {
    const cap = validateRealizedRrAgainstTargeted(saveSource)
    if (cap != null) {
      if (earlyExit && pnl > 0) {
        const canCompute = canComputeRealizedRrFromPricesAndPlan({
          points: args.pointsRaw,
          rr: args.targetedRrRaw,
          entry_price: args.entryPriceRaw,
          exit_price: args.exitPriceRaw,
          direction: args.direction,
        })
        if (!canCompute) {
          errors.exitRr = cap
        } else {
          errors.realizedRr = cap
        }
      } else {
        errors.realizedRr = cap
      }
      errors.ok = false
    }
  }

  return errors
}

export function realizedRrForManualTradeSave(
  trade: ManualTradeSaveSource
): number | null {
  const pnl = Number(trade.pnl)
  const targeted = parsePositiveTargetedRr(trade.rr)
  if (trade.full_tp === true && Number.isFinite(pnl) && pnl > 0 && targeted != null) {
    return targeted
  }
  if (
    trade.early_exit === true &&
    Number.isFinite(pnl) &&
    pnl > 0
  ) {
    const computed = computeRealizedRrFromPricesAndPlan(trade)
    if (computed != null) return computed
    if (hasStoredRr(trade.exit_rr)) {
      const manual = Number(trade.exit_rr)
      if (isPlausibleRealizedRr(manual)) return manual
    }
    return null
  }
  return computeRealizedRrFromPricesAndPlan(trade)
}

/** Dashboard Avg Targeted R:R — mean stored targeted `rr`; ignores missing values. */
export function averageTargetedRrFromTrades(
  trades: TradeRealizedRrSource[]
): number | null {
  let sum = 0
  let count = 0
  for (const trade of trades) {
    const rr = parsePositiveTargetedRr(trade.rr)
    if (rr == null) continue
    sum += rr
    count += 1
  }
  return count > 0 ? sum / count : null
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
