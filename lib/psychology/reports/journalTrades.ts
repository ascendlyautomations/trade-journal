import { isBacktestTrade } from "../../tradeModeFilters.ts"
import { rpcTradesOwnerRows } from "../../tradeOwnerRead.ts"
import { supabase } from "../../supabaseClient.ts"
import { PSYCHOLOGY_REPORT_TRADE_CAP, type PsychologyReportTrade } from "./types.ts"

type JournalCache = {
  userId: string
  fingerprint: string
  trades: PsychologyReportTrade[]
}

let journalCache: JournalCache | null = null
const inFlight = new Map<string, Promise<PsychologyReportTrade[]>>()

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

function asBoolean(value: unknown): boolean | null {
  if (value == null || value === "") return null
  if (typeof value === "boolean") return value
  if (value === true || value === "true" || value === 1 || value === "1") return true
  if (value === false || value === "false" || value === 0 || value === "0") return false
  return null
}

export function mapPsychologyReportTrade(
  row: Record<string, unknown>
): PsychologyReportTrade | null {
  const id = asText(row.id)
  if (!id) return null
  const entryTime = asText(row.entry_time) ?? asText(row.created_at) ?? ""
  const entryAtMs = entryTime ? Date.parse(entryTime) : Number.NaN
  return {
    id,
    entryAtMs: Number.isFinite(entryAtMs) ? entryAtMs : 0,
    entry_time: entryTime,
    created_at: asText(row.created_at),
    pnl: asNumber(row.pnl) ?? 0,
    rr: asNumber(row.rr),
    mode: asText(row.mode),
    account_type: asText(row.account_type),
    emotion: asText(row.emotion),
    confidence: asNumber(row.confidence),
    followedPlan: asBoolean(row.followed_plan),
    executionRating: asNumber(row.execution_rating),
  }
}

export function journalTradeFingerprint(
  trades: ReadonlyArray<{ id?: unknown; updated_at?: unknown; created_at?: unknown }>
): string {
  const ids = trades
    .map((row) => String(row.id ?? ""))
    .filter(Boolean)
    .slice(0, PSYCHOLOGY_REPORT_TRADE_CAP)
  return `${ids.length}:${ids[0] ?? ""}:${ids[ids.length - 1] ?? ""}`
}

function capRecentDashboardTrades<T extends { id?: unknown; entry_time?: unknown; created_at?: unknown }>(
  trades: readonly T[]
): T[] {
  return [...trades]
    .sort((a, b) => {
      const aTime = Date.parse(String(a.entry_time ?? a.created_at ?? "")) || 0
      const bTime = Date.parse(String(b.entry_time ?? b.created_at ?? "")) || 0
      return bTime - aTime
    })
    .slice(0, PSYCHOLOGY_REPORT_TRADE_CAP)
}

export function readPsychologyJournalCache(
  userId: string,
  fingerprint: string
): PsychologyReportTrade[] | undefined {
  if (!journalCache) return undefined
  if (journalCache.userId !== userId || journalCache.fingerprint !== fingerprint) {
    return undefined
  }
  return journalCache.trades
}

export async function ensurePsychologyJournalTrades(
  userId: string,
  dashboardTrades: ReadonlyArray<Record<string, unknown>>
): Promise<PsychologyReportTrade[]> {
  const eligible = dashboardTrades.filter((row) => !isBacktestTrade(row))
  const capped = capRecentDashboardTrades(eligible)
  const fingerprint = journalTradeFingerprint(capped)
  const cached = readPsychologyJournalCache(userId, fingerprint)
  if (cached) return cached

  const existing = inFlight.get(`${userId}:${fingerprint}`)
  if (existing) return existing

  const task = (async () => {
    const ids = capped
      .map((row) => String(row.id ?? "").trim())
      .filter(Boolean)
    const { rows, error } = await rpcTradesOwnerRows(supabase, {
      tradeIds: ids.length ? ids : undefined,
      limit: ids.length ? undefined : PSYCHOLOGY_REPORT_TRADE_CAP,
    })
    if (error) throw error
    const mapped = (rows.length ? rows : capped)
      .map((row) => mapPsychologyReportTrade(row))
      .filter((row): row is PsychologyReportTrade => row != null)
      .filter((row) => !isBacktestTrade(row))
      .sort((a, b) => b.entryAtMs - a.entryAtMs)
      .slice(0, PSYCHOLOGY_REPORT_TRADE_CAP)
    journalCache = { userId, fingerprint, trades: mapped }
    return mapped
  })().finally(() => {
    inFlight.delete(`${userId}:${fingerprint}`)
  })

  inFlight.set(`${userId}:${fingerprint}`, task)
  return task
}

/** @internal */
export function resetPsychologyJournalCacheForTests(): void {
  journalCache = null
  inFlight.clear()
}
