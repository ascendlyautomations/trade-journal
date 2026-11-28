import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import { averageRrFromTrades } from "@/lib/tradeRr"
import type { AiPortfolioScope } from "@/lib/server/ai/aiConversationTypes"
import { fetchPsychologyCheckInWindowRpc } from "@/lib/dailyCheckIn/fetchPsychologyCheckInWindowRpc"
import {
  formatTradingRulesContextBlock,
  loadTradingRulesAnalyticsForUser,
} from "@/lib/server/ai/aiTradingRulesContext"

type Db = SupabaseClient<Database>

const MAX_TRADE_ROWS = 400
const MAX_CSV_TRADES = 120

const TRADE_SELECT =
  "id,ticker,pnl,rr,realized_rr,max_rr_reached,direction,session,strategy,trade_date,date,entry_time,created_at,duration_seconds,contracts,dollar_risk,mistake_type,followed_plan,emotion,confidence,psychology_notes,account_id,entry_price,exit_price"

export type PortfolioContextResult = {
  scopeLabel: string
  statisticsBlock: string
  tradesCsvBlock: string
  limitations: string[]
}

function resolveDateRange(scope: AiPortfolioScope): {
  start: string | null
  end: string | null
  label: string
  priorStart: string | null
  priorEnd: string | null
} {
  const now = new Date()
  const end = scope.endDate?.trim() || now.toISOString().slice(0, 10)

  const rangeDays = (start: Date, endDate: Date) =>
    Math.max(1, Math.round((endDate.getTime() - start.getTime()) / 86_400_000))

  switch (scope.preset) {
    case "last_7": {
      const d = new Date(now)
      d.setDate(d.getDate() - 7)
      const priorEnd = new Date(d)
      priorEnd.setDate(priorEnd.getDate() - 1)
      const priorStart = new Date(priorEnd)
      priorStart.setDate(priorStart.getDate() - 7)
      return {
        start: d.toISOString().slice(0, 10),
        end,
        label: "Last 7 days",
        priorStart: priorStart.toISOString().slice(0, 10),
        priorEnd: priorEnd.toISOString().slice(0, 10),
      }
    }
    case "last_30": {
      const d = new Date(now)
      d.setDate(d.getDate() - 30)
      const priorEnd = new Date(d)
      priorEnd.setDate(priorEnd.getDate() - 1)
      const priorStart = new Date(priorEnd)
      priorStart.setDate(priorStart.getDate() - 30)
      return {
        start: d.toISOString().slice(0, 10),
        end,
        label: "Last 30 days",
        priorStart: priorStart.toISOString().slice(0, 10),
        priorEnd: priorEnd.toISOString().slice(0, 10),
      }
    }
    case "last_90": {
      const d = new Date(now)
      d.setDate(d.getDate() - 90)
      const priorEnd = new Date(d)
      priorEnd.setDate(priorEnd.getDate() - 1)
      const priorStart = new Date(priorEnd)
      priorStart.setDate(priorStart.getDate() - 90)
      return {
        start: d.toISOString().slice(0, 10),
        end,
        label: "Last 90 days",
        priorStart: priorStart.toISOString().slice(0, 10),
        priorEnd: priorEnd.toISOString().slice(0, 10),
      }
    }
    case "custom":
      if (scope.startDate && scope.endDate) {
        const start = new Date(scope.startDate)
        const endDate = new Date(scope.endDate)
        const days = rangeDays(start, endDate)
        const priorEnd = new Date(start)
        priorEnd.setDate(priorEnd.getDate() - 1)
        const priorStart = new Date(priorEnd)
        priorStart.setDate(priorStart.getDate() - days)
        return {
          start: scope.startDate,
          end: scope.endDate,
          label: "Custom date range",
          priorStart: priorStart.toISOString().slice(0, 10),
          priorEnd: priorEnd.toISOString().slice(0, 10),
        }
      }
      return {
        start: scope.startDate ?? null,
        end: scope.endDate ?? end,
        label: "Custom date range",
        priorStart: null,
        priorEnd: null,
      }
    case "all_time":
    default:
      return {
        start: null,
        end: null,
        label: "All time",
        priorStart: null,
        priorEnd: null,
      }
  }
}

function csvEscape(value: unknown): string {
  const raw = value == null ? "" : String(value)
  if (raw.includes(",") || raw.includes('"') || raw.includes("\n")) {
    return `"${raw.replace(/"/g, '""')}"`
  }
  return raw
}

function aggregatePsychologyFromTrades(trades: Record<string, unknown>[]): string {
  const followed = trades.filter((t) => t.followed_plan === true).length
  const withEmotion = trades.filter((t) => hasText(t.emotion)).length
  const mistakes = trades.filter((t) => hasText(t.mistake_type)).length
  return `Trade-tagged psychology (sample=${trades.length}):
- followed_plan=true: ${followed}
- trades with emotion logged: ${withEmotion}
- trades with mistake_type: ${mistakes}`
}

function hasText(value: unknown): boolean {
  return typeof value === "string" && value.trim().length > 0
}

async function fetchScopedTrades(
  db: Db,
  userId: string,
  range: { start: string | null; end: string | null },
  scope: AiPortfolioScope
) {
  let query = db
    .from("trades")
    .select(TRADE_SELECT)
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(MAX_TRADE_ROWS)

  if (range.start) query = query.gte("trade_date", range.start)
  if (range.end) query = query.lte("trade_date", range.end)

  if (Array.isArray(scope.accountIds) && scope.accountIds.length > 0) {
    query = query.in("account_id", scope.accountIds)
  } else if (scope.accountIds === "all" || !scope.accountIds) {
    // no filter
  }

  const { data, error } = await query
  return { trades: data ?? [], error }
}

function statsForTrades(trades: Record<string, unknown>[]) {
  const priced = trades.filter((t) => t.pnl != null && Number.isFinite(Number(t.pnl)))
  const wins = priced.filter((t) => Number(t.pnl) > 0).length
  const winRate =
    priced.length > 0 ? ((wins / priced.length) * 100).toFixed(1) : null
  const net = priced.reduce((s, t) => s + Number(t.pnl), 0)
  const avgRr = averageRrFromTrades(trades)
  return { priced, winRate, net, avgRr, count: trades.length }
}

export async function buildPortfolioAnalysisContext(
  db: Db,
  userId: string,
  scope: AiPortfolioScope
): Promise<PortfolioContextResult> {
  const range = resolveDateRange(scope)
  const limitations: string[] = []

  const { trades, error } = await fetchScopedTrades(db, userId, range, scope)
  if (error) limitations.push(`Trade query failed: ${error.message}`)
  if (trades.length >= MAX_TRADE_ROWS) {
    limitations.push(
      `Trade list capped at ${MAX_TRADE_ROWS} most recent rows in scope. Aggregates use this sample only.`
    )
  }

  const current = statsForTrades(trades)

  let comparisonBlock = ""
  if (range.priorStart && range.priorEnd) {
    const prior = await fetchScopedTrades(
      db,
      userId,
      { start: range.priorStart, end: range.priorEnd },
      scope
    )
    const prev = statsForTrades(prior.trades)
    comparisonBlock = `PRIOR PERIOD COMPARISON (${range.priorStart} – ${range.priorEnd}, sample=${prev.count}):
- Win rate: ${prev.winRate ?? "n/a"}% vs current ${current.winRate ?? "n/a"}%
- Net P&L: ${prev.net.toFixed(2)} vs current ${current.net.toFixed(2)}
- Avg RR: ${prev.avgRr?.toFixed(2) ?? "n/a"} vs current ${current.avgRr?.toFixed(2) ?? "n/a"}`
  }

  const bySession = new Map<string, { n: number; net: number }>()
  const byTicker = new Map<string, { n: number; net: number }>()
  const byStrategy = new Map<string, { n: number; net: number }>()
  for (const t of trades) {
    const pnl = Number(t.pnl)
    const p = Number.isFinite(pnl) ? pnl : 0
    const bump = (map: Map<string, { n: number; net: number }>, key: string) => {
      const k = key.trim() || "(not logged)"
      const cur = map.get(k) ?? { n: 0, net: 0 }
      cur.n += 1
      if (Number.isFinite(pnl)) cur.net += p
      map.set(k, cur)
    }
    bump(bySession, String(t.session ?? ""))
    bump(byTicker, String(t.ticker ?? ""))
    bump(byStrategy, String(t.strategy ?? ""))
  }

  const topLines = (label: string, map: Map<string, { n: number; net: number }>) => {
    const sorted = [...map.entries()].sort((a, b) => b[1].net - a[1].net)
    const lines = sorted.slice(0, 6).map(([k, v]) => `  - ${k}: n=${v.n}, net P&L ${v.net.toFixed(2)}`)
    return `${label} (sample=${trades.length}):\n${lines.join("\n") || "  - (no data)"}`
  }

  let checkInBlock = "Daily check-ins: not loaded for portfolio scope."
  try {
    const accountId =
      Array.isArray(scope.accountIds) && scope.accountIds.length === 1
        ? scope.accountIds[0]
        : undefined
    const checkIns = await fetchPsychologyCheckInWindowRpc(db, accountId)
    const inRange = checkIns.filter((c) => {
      if (!range.start && !range.end) return true
      if (range.start && c.checkInDate < range.start) return false
      if (range.end && c.checkInDate > range.end) return false
      return true
    })
    if (inRange.length === 0) {
      checkInBlock = `Daily check-ins in scope: none (${range.label}).`
    } else {
      const avgStress =
        inRange.reduce((s, c) => s + (c.stressLevel ?? 0), 0) / inRange.length
      checkInBlock = `Daily check-ins in scope: n=${inRange.length}, avg stress ${avgStress.toFixed(1)}/5 (1=calm).`
    }
  } catch {
    checkInBlock = "Daily check-ins: unavailable."
  }

  let rulesBlock = "TRADING RULES: unavailable."
  try {
    const rulesAnalytics = await loadTradingRulesAnalyticsForUser(db, userId, trades)
    rulesBlock = formatTradingRulesContextBlock(rulesAnalytics)
  } catch {
    rulesBlock = "TRADING RULES: failed to load."
  }

  const statisticsBlock = [
    `SCOPE: ${range.label}`,
    range.start ? `Start: ${range.start}` : "Start: (unbounded)",
    range.end ? `End: ${range.end}` : "End: (unbounded)",
    `Account filter: ${
      Array.isArray(scope.accountIds)
        ? scope.accountIds.join(", ")
        : "all accounts"
    }`,
    `Trades in sample: ${current.count}`,
    `Priced trades: ${current.priced.length}`,
    current.winRate != null
      ? `Win rate: ${current.winRate}% (priced sample)`
      : "Win rate: (insufficient priced trades)",
    `Net P&L (priced): ${current.net.toFixed(2)}`,
    current.avgRr != null
      ? `Average RR: ${current.avgRr.toFixed(2)}`
      : "Average RR: (not available)",
    comparisonBlock,
    topLines("By session", bySession),
    topLines("By ticker", byTicker),
    topLines("By strategy", byStrategy),
    aggregatePsychologyFromTrades(trades),
    checkInBlock,
    rulesBlock,
  ]
    .filter(Boolean)
    .join("\n")

  const csvHeader =
    "id,date,ticker,direction,session,strategy,pnl,rr,realized_rr,contracts,dollar_risk,followed_plan,mistake_type,emotion"
  const csvRows = trades.slice(0, MAX_CSV_TRADES).map((t) =>
    [
      t.id,
      t.trade_date ?? t.date,
      t.ticker,
      t.direction,
      t.session,
      t.strategy,
      t.pnl,
      t.rr,
      t.realized_rr,
      t.contracts,
      t.dollar_risk,
      t.followed_plan,
      t.mistake_type,
      t.emotion,
    ]
      .map(csvEscape)
      .join(",")
  )

  if (trades.length > MAX_CSV_TRADES) {
    limitations.push(
      `CSV detail includes ${MAX_CSV_TRADES} most recent trades; ${trades.length - MAX_CSV_TRADES} older rows omitted from row-level detail but aggregates use full sample up to cap.`
    )
  }

  return {
    scopeLabel: range.label,
    statisticsBlock,
    tradesCsvBlock: [csvHeader, ...csvRows].join("\n"),
    limitations,
  }
}