import { getDashboardTradingDayKey } from "../dashboardTradeDate.ts"
import { psychologyTradeDateKey } from "../psychology/tradeDateKey.ts"
import { hasStoredRr } from "../tradeRr.ts"
import { resolveRealizedRr } from "../tradePointsAndRealizedRr.ts"
import type { PsychologyReportTrade } from "../psychology/reports/types.ts"
import type { ScorecardTrade } from "./types.ts"

function asBoolean(value: unknown): boolean | null {
  if (value == null || value === "") return null
  if (typeof value === "boolean") return value
  if (value === true || value === "true" || value === 1 || value === "1") return true
  if (value === false || value === "false" || value === 0 || value === "0") return false
  return null
}

function asNumber(value: unknown): number | null {
  if (value == null || value === "") return null
  const parsed = typeof value === "number" ? value : Number(value)
  return Number.isFinite(parsed) ? parsed : null
}

function asText(value: unknown): string | null {
  if (value == null) return null
  const trimmed = String(value).trim()
  return trimmed ? trimmed : null
}

function psychologyDayKeyFromFields(
  entryTimeIso: string,
  row?: Record<string, unknown>
): string | null {
  const key = psychologyTradeDateKey({
    entry_time: entryTimeIso,
    created_at: row ? asText(row.created_at) : entryTimeIso,
    date: row ? asText(row.date) : null,
    trade_date: row ? asText(row.trade_date) : null,
  })
  return key || null
}

export function mapDashboardRowToScorecardTrade(
  row: Record<string, unknown>
): ScorecardTrade | null {
  const id = asText(row.id)
  if (!id) return null
  const entry = asText(row.entry_time) ?? asText(row.created_at) ?? ""
  const entryAtMs = entry ? Date.parse(entry) : Number.NaN
  if (!Number.isFinite(entryAtMs)) return null

  const rr = hasStoredRr(row.rr) ? Number(row.rr) : null
  const maxRr = hasStoredRr(row.max_rr_reached) ? Number(row.max_rr_reached) : null
  const realized = resolveRealizedRr(row)
  const entryIso = entry || new Date(entryAtMs).toISOString()

  return {
    id,
    pnl: asNumber(row.pnl) ?? 0,
    rr,
    maxRrReached: maxRr,
    realizedRr: realized,
    followedPlan: asBoolean(row.followed_plan),
    mistakeType: asText(row.mistake_type),
    confidence: asNumber(row.confidence),
    executionRating: asNumber(row.execution_rating),
    entryTimeMs: entryAtMs,
    tradingDayKey: getDashboardTradingDayKey(row),
    psychologyDayKey: psychologyDayKeyFromFields(entryIso, row),
  }
}

export function mergeScorecardTrades(
  dashboardRows: readonly Record<string, unknown>[],
  journalTrades: readonly PsychologyReportTrade[]
): ScorecardTrade[] {
  const byId = new Map<string, ScorecardTrade>()
  for (const row of dashboardRows) {
    const mapped = mapDashboardRowToScorecardTrade(row)
    if (mapped) byId.set(mapped.id, mapped)
  }
  for (const journal of journalTrades) {
    const existing = byId.get(journal.id)
    const entryIso =
      journal.entry_time || new Date(journal.entryAtMs).toISOString()
    const psychologyDayKey =
      existing?.psychologyDayKey ?? psychologyDayKeyFromFields(entryIso)
    byId.set(journal.id, {
      id: journal.id,
      pnl: journal.pnl,
      rr: journal.rr ?? existing?.rr ?? null,
      maxRrReached: existing?.maxRrReached ?? null,
      realizedRr: journal.realizedRr ?? existing?.realizedRr ?? null,
      followedPlan: journal.followedPlan ?? existing?.followedPlan ?? null,
      mistakeType: existing?.mistakeType ?? null,
      confidence: journal.confidence ?? existing?.confidence ?? null,
      executionRating: journal.executionRating ?? existing?.executionRating ?? null,
      entryTimeMs: journal.entryAtMs,
      tradingDayKey: existing?.tradingDayKey ?? null,
      psychologyDayKey,
    })
  }
  return [...byId.values()].sort((a, b) => a.entryTimeMs - b.entryTimeMs)
}

export function postTripleLossWinRate(trades: readonly ScorecardTrade[]): number | null {
  if (trades.length < 4) return null
  for (let i = 0; i <= trades.length - 4; i++) {
    const a = trades[i].pnl
    const b = trades[i + 1].pnl
    const c = trades[i + 2].pnl
    if (a < 0 && b < 0 && c < 0) {
      const next = trades.slice(i + 3, i + 8)
      if (next.length === 0) return null
      const wins = next.filter((t) => t.pnl > 0).length
      return wins / next.length
    }
  }
  return null
}
