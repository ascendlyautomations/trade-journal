import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import {
  buildAnalyzeTradeHistoryContext,
  formatTradeDataSection,
} from "@/lib/analyzeTradePrompt"
import {
  formatTradingRulesContextBlock,
  loadTradingRulesAnalyticsForUser,
} from "@/lib/server/ai/aiTradingRulesContext"
import { fetchPsychologyCheckInWindowRpc } from "@/lib/dailyCheckIn/fetchPsychologyCheckInWindowRpc"
import { psychologyTradeDateKey } from "@/lib/psychology/tradeDateKey"

const TRADE_SELECT =
  "id,user_id,account_id,ticker,direction,pnl,rr,realized_rr,max_rr_reached,full_tp,early_exit,exit_rr,entry_price,exit_price,entry_time,exit_time,trade_date,date,session,strategy,mode,contracts,dollar_risk,points,notes,public_description,top_confluences,mistake_type,confidence,emotion,followed_plan,psychology_notes,exit_emotion,execution_rating,account_type,trade_mode,duration_seconds,duration_text,image_url,created_at"

type Db = SupabaseClient<Database>

function present(value: unknown): boolean {
  if (value == null) return false
  if (typeof value === "string") return value.trim().length > 0
  if (typeof value === "number") return Number.isFinite(value)
  if (Array.isArray(value)) return value.length > 0
  return true
}

function formatNullable(label: string, value: unknown, lines: string[]) {
  if (!present(value)) {
    lines.push(`${label}: (not logged)`)
    return
  }
  lines.push(`${label}: ${String(value)}`)
}

function formatCheckInSection(checkIn: Record<string, unknown> | null): string {
  if (!checkIn) {
    return "DAILY PSYCHOLOGY CHECK-IN: No check-in found for this trade date (not missing as zero — data unavailable)."
  }
  const lines: string[] = ["DAILY PSYCHOLOGY CHECK-IN (same trading day):"]
  const fields: Array<[string, string]> = [
    ["Morning rating", "morningRating"],
    ["Energy", "energyLevel"],
    ["Stress", "stressLevel"],
    ["Focus", "focusLevel"],
    ["Sleep hours", "sleepHours"],
    ["Sleep quality", "sleepQuality"],
    ["Notes", "notes"],
  ]
  for (const [label, key] of fields) {
    formatNullable(label, checkIn[key], lines)
  }
  return lines.join("\n")
}

export type AuthoritativeTradeContext = {
  tradeForPrompt: Record<string, unknown>
  historyContextText: string
  supplementalSections: string
  imagePath: string | null
  accountLabel: string | null
}

export async function buildAuthoritativeTradeContext(
  db: Db,
  userId: string,
  tradeId: string
): Promise<AuthoritativeTradeContext | null> {
  const { data: tradeRow, error: tradeError } = await db
    .from("trades")
    .select(TRADE_SELECT)
    .eq("id", tradeId)
    .eq("user_id", userId)
    .maybeSingle()

  if (tradeError || !tradeRow) return null

  let accountLabel: string | null = null
  if (tradeRow.account_id) {
    const { data: account } = await db
      .from("accounts")
      .select("name, mode, category")
      .eq("id", tradeRow.account_id)
      .maybeSingle()
    accountLabel = account?.name?.trim() || null
  }

  const { data: historyRows } = await db
    .from("trades")
    .select(
      "id, ticker, pnl, rr, direction, session, strategy, created_at, duration_seconds, duration_text, entry_time, exit_time"
    )
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(120)

  const historyContext = buildAnalyzeTradeHistoryContext(
    (historyRows ?? []) as Record<string, unknown>[],
    tradeId
  )

  const tradeForPrompt: Record<string, unknown> = {
    ...tradeRow,
    confluences: tradeRow.top_confluences,
    psychology: tradeRow.psychology_notes,
    mistakes: tradeRow.mistake_type,
    trade_date: tradeRow.trade_date ?? tradeRow.date,
  }

  const psychologyLines: string[] = ["PSYCHOLOGY & DISCIPLINE (trade fields):"]
  formatNullable("Confidence", tradeRow.confidence, psychologyLines)
  formatNullable("Emotion", tradeRow.emotion, psychologyLines)
  formatNullable("Exit emotion", tradeRow.exit_emotion, psychologyLines)
  formatNullable("Followed plan", tradeRow.followed_plan, psychologyLines)
  formatNullable("Execution rating", tradeRow.execution_rating, psychologyLines)
  formatNullable("Mistake type", tradeRow.mistake_type, psychologyLines)
  formatNullable("Psychology notes", tradeRow.psychology_notes, psychologyLines)

  const rrLines: string[] = ["RISK / REWARD (explicit — missing ≠ zero):"]
  formatNullable("Planned / stored RR", tradeRow.rr, rrLines)
  formatNullable("Realized RR", tradeRow.realized_rr, rrLines)
  formatNullable("Max RR reached", tradeRow.max_rr_reached, rrLines)
  formatNullable("Exit RR", tradeRow.exit_rr, rrLines)
  formatNullable("Full take-profit", tradeRow.full_tp, rrLines)
  formatNullable("Early exit flag", tradeRow.early_exit, rrLines)
  formatNullable("Dollar risk", tradeRow.dollar_risk, rrLines)

  const economicsLines: string[] = ["ECONOMICS:"]
  formatNullable("P&L", tradeRow.pnl, economicsLines)
  formatNullable("Contracts / size", tradeRow.contracts, economicsLines)
  formatNullable("Points", tradeRow.points, economicsLines)
  economicsLines.push("Commissions: (not stored per trade — do not invent).")

  const metaLines: string[] = ["TRADE META:"]
  formatNullable("Account", accountLabel ?? tradeRow.account_type, metaLines)
  formatNullable("Account type", tradeRow.account_type, metaLines)
  formatNullable("Trade mode", tradeRow.trade_mode ?? tradeRow.mode, metaLines)
  formatNullable("Strategy", tradeRow.strategy, metaLines)
  formatNullable("Session", tradeRow.session, metaLines)
  formatNullable("Setup / confluences", tradeRow.top_confluences, metaLines)

  let checkInBlock = "DAILY PSYCHOLOGY CHECK-IN: (not loaded)"
  try {
    const dayKey = psychologyTradeDateKey({
      trade_date: tradeRow.trade_date ?? tradeRow.date,
      entry_time: tradeRow.entry_time,
      created_at: tradeRow.created_at,
    })
  const checkIns = await fetchPsychologyCheckInWindowRpc(
      db,
      tradeRow.account_id ?? undefined
    )
    const match = checkIns.find((c) => c.checkInDate === dayKey)
    checkInBlock = formatCheckInSection(
      match ? (match as unknown as Record<string, unknown>) : null
    )
  } catch {
    checkInBlock =
      "DAILY PSYCHOLOGY CHECK-IN: Unable to load check-ins for this trade date."
  }

  let rulesBlock =
    "TRADING RULES: Preference data unavailable — do not infer compliance."
  try {
    const complianceRows = [...(historyRows ?? []), tradeRow]
    const rulesAnalytics = await loadTradingRulesAnalyticsForUser(
      db,
      userId,
      complianceRows as Record<string, unknown>[]
    )
    rulesBlock = formatTradingRulesContextBlock(rulesAnalytics, { tradeId })
  } catch {
    rulesBlock = "TRADING RULES: Evaluation failed to load — skip compliance claims."
  }

  const supplementalSections = [
    metaLines.join("\n"),
    economicsLines.join("\n"),
    rrLines.join("\n"),
    psychologyLines.join("\n"),
    checkInBlock,
    rulesBlock,
    "",
    "STRUCTURED TRADE FIELDS:",
    formatTradeDataSection(tradeForPrompt),
  ].join("\n\n")

  return {
    tradeForPrompt,
    historyContextText:
      historyContext?.summaryText ??
      "TRADER HISTORY: No prior trades available for comparison.",
    supplementalSections,
    imagePath: tradeRow.image_url ?? null,
    accountLabel,
  }
}