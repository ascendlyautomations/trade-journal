import { COMPARATIVE_MIN_PER_SIDE } from "@/lib/analytics/knownPnl"
import {
  complianceTradeFromRow,
  easternMinuteOfDay,
  rulesActiveAt,
  type ComplianceTrade,
  type PreferenceRuleContext,
} from "@/lib/analytics/preferenceCompliance"
import {
  scopedDayBucket,
  scopedWeekBucket,
  scopeBucketLabel,
  weekdayDisplayLabel,
  type TradingRuleScope,
} from "@/lib/analytics/tradingRuleScope"
import type { ResolvedTradingPreferences } from "@/lib/analytics/tradingPreferences"

export type RuleCheckOutcome = "followed" | "violated" | "unevaluated"

export type RuleCheckLevel = "trade" | "day" | "week"

export type RuleCheckId =
  | "preferred_session"
  | "primary_instrument"
  | "planned_hours"
  | "allowed_trading_day"
  | "min_planned_rr"
  | "max_contracts"
  | "max_risk_per_trade"
  | "target_rr_max"
  | "max_trades_per_day"
  | "daily_loss_limit"
  | "daily_profit_stop"
  | "weekly_loss_limit"

const RULE_LABELS: Record<RuleCheckId, string> = {
  preferred_session: "Preferred session",
  primary_instrument: "Primary instrument",
  planned_hours: "Planned trading hours",
  allowed_trading_day: "Allowed trading day",
  min_planned_rr: "Minimum planned R:R",
  max_contracts: "Maximum contracts per trade",
  max_risk_per_trade: "Maximum risk per trade",
  target_rr_max: "Target R:R (max reached)",
  max_trades_per_day: "Daily trade cap",
  daily_loss_limit: "Daily loss limit",
  daily_profit_stop: "Daily profit stop",
  weekly_loss_limit: "Weekly loss limit",
}

export type RuleCheckRecord = {
  id: string
  ruleId: RuleCheckId
  ruleLabel: string
  outcome: RuleCheckOutcome
  level: RuleCheckLevel
  atMs: number
  dayKey: string
  weekKey: string | null
  monthKey: string
  tradeId: string | null
  accountId: string | null
  scopeLabel: string | null
  detail: string
  pnl: number | null
}

export type RuleViolationEvent = {
  id: string
  atMs: number
  dayKey: string
  tradeId: string | null
  accountId: string | null
  accountLabel: string | null
  ruleId: RuleCheckId
  ruleLabel: string
  level: RuleCheckLevel
  scopeLabel: string | null
  summary: string
}

type ImpactSide = {
  priced: number
  wins: number
  totalPnl: number
}

export type RuleImpactRow = {
  ruleId: RuleCheckId
  ruleLabel: string
  followed: ImpactSide
  violated: ImpactSide
  sufficientSample: boolean
  winRateFollowed: number | null
  winRateViolated: number | null
  avgPnlFollowed: number | null
  avgPnlViolated: number | null
  summary: string | null
}

export type ComplianceScoreSummary = {
  adherencePercent: number | null
  followed: number
  violated: number
  unevaluated: number
  evaluated: number
  explanation: string
}

export type ComplianceTrendPoint = {
  key: string
  label: string
  adherencePercent: number | null
  evaluated: number
  violations: number
  insufficientData: boolean
  coverageNote: string | null
}

export type TradingRulesComplianceAnalytics = {
  score: ComplianceScoreSummary
  impacts: RuleImpactRow[]
  violations: RuleViolationEvent[]
  weeklyTrend: ComplianceTrendPoint[]
  monthlyTrend: ComplianceTrendPoint[]
  usesHistoricalRevisions: boolean
}

function minuteInWindow(minute: number, start: number, end: number): boolean {
  if (end > start) return minute >= start && minute < end
  return minute >= start || minute < end
}

function monthKeyFromDayKey(dayKey: string): string {
  return dayKey.length >= 7 ? dayKey.slice(0, 7) : dayKey
}

function emptySide(): ImpactSide {
  return { priced: 0, wins: 0, totalPnl: 0 }
}

function addImpact(side: ImpactSide, pnl: number | null) {
  if (pnl == null) return
  side.priced += 1
  side.totalPnl += pnl
  if (pnl > 0) side.wins += 1
}

function winRate(side: ImpactSide): number | null {
  return side.priced > 0 ? side.wins / side.priced : null
}

function avgPnl(side: ImpactSide): number | null {
  return side.priced > 0 ? side.totalPnl / side.priced : null
}

function formatMoney(value: number): string {
  const abs = Math.abs(value).toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
  return value < 0 ? `-$${abs}` : `$${abs}`
}

function formatPct(rate: number): string {
  return `${Math.round(rate * 100)}%`
}

let checkSeq = 0

function pushCheck(
  checks: RuleCheckRecord[],
  event: Omit<RuleCheckRecord, "id" | "ruleLabel"> & { ruleId: RuleCheckId }
) {
  checkSeq += 1
  checks.push({
    ...event,
    id: `chk-${checkSeq}`,
    ruleLabel: RULE_LABELS[event.ruleId],
  })
}

function rulesFingerprint(rules: ResolvedTradingPreferences): string {
  return [
    rules.preferredSessions.join(","),
    rules.primaryInstruments.join(","),
    rules.plannedHours?.startMinute ?? "",
    rules.plannedHours?.endMinute ?? "",
    rules.maxTradesPerDay ?? "",
    rules.dailyLossLimit ?? "",
    rules.dailyProfitTarget ?? "",
    rules.stopAfterDailyProfitTarget ? "1" : "0",
    rules.maxWeeklyLoss ?? "",
    rules.minAcceptableRr ?? "",
    rules.maxContractsPerTrade ?? "",
    rules.maxRiskPerTrade ?? "",
    rules.targetRr ?? "",
    rules.allowedTradingDays.join(","),
    rules.maxTradesPerDayScope,
    rules.dailyLossLimitScope,
    rules.dailyProfitRulesScope,
    rules.maxWeeklyLossScope,
  ].join("|")
}

function buildTrend(
  checks: RuleCheckRecord[],
  keyFn: (row: RuleCheckRecord) => string,
  labelFn: (key: string) => string,
  context: PreferenceRuleContext | null | undefined,
  orderedTrades: ComplianceTrade[]
): ComplianceTrendPoint[] {
  const buckets = new Map<
    string,
    { followed: number; violated: number; fingerprint: string | null }
  >()

  for (const check of checks) {
    if (check.outcome === "unevaluated") continue
    const key = keyFn(check)
    const bucket = buckets.get(key) ?? {
      followed: 0,
      violated: 0,
      fingerprint: null,
    }
    if (check.outcome === "followed") bucket.followed += 1
    else bucket.violated += 1
    buckets.set(key, bucket)
  }

  const coverageByKey = new Map<string, Set<string>>()
  for (const trade of orderedTrades) {
    const rules = rulesActiveAt(context, trade.atMs, trade.accountId)
    const fp = rulesFingerprint(rules)
    const wk = trade.weekKey ?? trade.dayKey
    const mk = monthKeyFromDayKey(trade.dayKey)
    for (const key of [wk, mk]) {
      if (!key) continue
      const set = coverageByKey.get(key) ?? new Set<string>()
      set.add(fp)
      coverageByKey.set(key, set)
    }
  }

  return [...buckets.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, bucket]) => {
      const evaluated = bucket.followed + bucket.violated
      const adherence =
        evaluated > 0 ? Math.round((bucket.followed / evaluated) * 1000) / 10 : null
      const insufficient = evaluated < 3
      const coverage = coverageByKey.get(key)
      const coverageNote =
        coverage != null && coverage.size > 1
          ? "Rule configuration changed during this period — compare cautiously."
          : null
      return {
        key,
        label: labelFn(key),
        adherencePercent: insufficient ? null : adherence,
        evaluated,
        violations: bucket.violated,
        insufficientData: insufficient,
        coverageNote,
      }
    })
}

export function buildTradingRulesComplianceAnalytics(
  trades: readonly ComplianceTrade[],
  context: PreferenceRuleContext | null | undefined,
  options?: { accountNames?: Record<string, string> }
): TradingRulesComplianceAnalytics {
  const checks: RuleCheckRecord[] = []
  const impacts = new Map<RuleCheckId, { followed: ImpactSide; violated: ImpactSide }>()
  for (const ruleId of Object.keys(RULE_LABELS) as RuleCheckId[]) {
    impacts.set(ruleId, { followed: emptySide(), violated: emptySide() })
  }

  const ordered = [...trades].sort((a, b) => a.atMs - b.atMs)
  const byCapDay = new Map<string, ComplianceTrade[]>()
  const byLossDay = new Map<string, ComplianceTrade[]>()
  const byProfitDay = new Map<string, ComplianceTrade[]>()
  const byWeek = new Map<string, ComplianceTrade[]>()

  const recordTradeCheck = (
    ruleId: RuleCheckId,
    trade: ComplianceTrade,
    outcome: RuleCheckOutcome,
    level: RuleCheckLevel,
    scopeLabel: string | null,
    detail: string
  ) => {
    if (outcome === "unevaluated") return
    pushCheck(checks, {
      ruleId,
      outcome,
      level,
      atMs: trade.atMs,
      dayKey: trade.dayKey,
      weekKey: trade.weekKey,
      monthKey: monthKeyFromDayKey(trade.dayKey),
      tradeId: trade.tradeId,
      accountId: trade.accountId,
      scopeLabel,
      detail,
      pnl: trade.pnl,
    })
    const bucket = impacts.get(ruleId)!
    if (outcome === "followed") addImpact(bucket.followed, trade.pnl)
    else addImpact(bucket.violated, trade.pnl)
  }

  for (const trade of ordered) {
    const rules = rulesActiveAt(context, trade.atMs, trade.accountId)

    if (rules.preferredSessions.length > 0) {
      if (trade.session) {
        const inside = rules.preferredSessions.includes(
          trade.session as (typeof rules.preferredSessions)[number]
        )
        recordTradeCheck(
          "preferred_session",
          trade,
          inside ? "followed" : "violated",
          "trade",
          null,
          inside
            ? `Traded during ${trade.session}.`
            : `Traded during ${trade.session}, outside preferred sessions.`
        )
      }
    }

    if (rules.primaryInstruments.length > 0 && trade.symbol) {
      const inside = rules.primaryInstruments.includes(trade.symbol)
      recordTradeCheck(
        "primary_instrument",
        trade,
        inside ? "followed" : "violated",
        "trade",
        null,
        inside
          ? `${trade.symbol} is a primary instrument.`
          : `${trade.symbol} is outside primary instruments.`
      )
    }

    if (rules.plannedHours && trade.easternMinute != null) {
      const inside = minuteInWindow(
        trade.easternMinute,
        rules.plannedHours.startMinute,
        rules.plannedHours.endMinute
      )
      recordTradeCheck(
        "planned_hours",
        trade,
        inside ? "followed" : "violated",
        "trade",
        null,
        inside ? "Entry during planned hours." : "Entry outside planned hours."
      )
    }

    if (rules.allowedTradingDays.length > 0 && trade.weekday) {
      const inside = rules.allowedTradingDays.includes(trade.weekday)
      recordTradeCheck(
        "allowed_trading_day",
        trade,
        inside ? "followed" : "violated",
        "trade",
        null,
        inside
          ? `Traded on ${weekdayDisplayLabel(trade.weekday)}.`
          : `Traded on ${weekdayDisplayLabel(trade.weekday)}, outside allowed days.`
      )
    }

    if (rules.minAcceptableRr != null && trade.plannedRr != null) {
      const ok = trade.plannedRr >= rules.minAcceptableRr
      recordTradeCheck(
        "min_planned_rr",
        trade,
        ok ? "followed" : "violated",
        "trade",
        null,
        ok
          ? `Planned R:R ${trade.plannedRr} met minimum ${rules.minAcceptableRr}.`
          : `Planned R:R ${trade.plannedRr} below minimum ${rules.minAcceptableRr}.`
      )
    }

    if (rules.maxContractsPerTrade != null && trade.contracts != null) {
      const ok = trade.contracts <= rules.maxContractsPerTrade
      recordTradeCheck(
        "max_contracts",
        trade,
        ok ? "followed" : "violated",
        "trade",
        null,
        ok
          ? `${trade.contracts} contracts within cap ${rules.maxContractsPerTrade}.`
          : `${trade.contracts} contracts above cap ${rules.maxContractsPerTrade}.`
      )
    }

    if (rules.maxRiskPerTrade != null && trade.dollarRisk != null) {
      const ok = trade.dollarRisk <= rules.maxRiskPerTrade
      recordTradeCheck(
        "max_risk_per_trade",
        trade,
        ok ? "followed" : "violated",
        "trade",
        null,
        ok
          ? `Planned risk ${formatMoney(trade.dollarRisk)} within ${formatMoney(rules.maxRiskPerTrade)}.`
          : `Planned risk ${formatMoney(trade.dollarRisk)} above ${formatMoney(rules.maxRiskPerTrade)}.`
      )
    }

    if (rules.targetRr != null && trade.maxRr != null) {
      const ok = trade.maxRr >= rules.targetRr
      recordTradeCheck(
        "target_rr_max",
        trade,
        ok ? "followed" : "violated",
        "trade",
        null,
        ok
          ? `Max R ${trade.maxRr} reached target ${rules.targetRr}.`
          : `Max R ${trade.maxRr} below target ${rules.targetRr}.`
      )
    }

    const capRules = rules
    const capKey = scopedDayBucket(
      trade.dayKey,
      trade.accountId,
      capRules.maxTradesPerDayScope
    )
    const capList = byCapDay.get(capKey) ?? []
    capList.push(trade)
    byCapDay.set(capKey, capList)

    const lossKey = scopedDayBucket(
      trade.dayKey,
      trade.accountId,
      capRules.dailyLossLimitScope
    )
    const lossList = byLossDay.get(lossKey) ?? []
    lossList.push(trade)
    byLossDay.set(lossKey, lossList)

    const profitKey = scopedDayBucket(
      trade.dayKey,
      trade.accountId,
      capRules.dailyProfitRulesScope
    )
    const profitList = byProfitDay.get(profitKey) ?? []
    profitList.push(trade)
    byProfitDay.set(profitKey, profitList)

    if (trade.weekKey) {
      const weekKey = scopedWeekBucket(
        trade.weekKey,
        trade.accountId,
        capRules.maxWeeklyLossScope
      )
      const weekList = byWeek.get(weekKey) ?? []
      weekList.push(trade)
      byWeek.set(weekKey, weekList)
    }
  }

  const scopeFor = (scope: TradingRuleScope) => scopeBucketLabel(scope)

  for (const day of byCapDay.values()) {
    day.sort((a, b) => a.atMs - b.atMs)
    let index = 0
    for (const trade of day) {
      index += 1
      const rules = rulesActiveAt(context, trade.atMs, trade.accountId)
      if (rules.maxTradesPerDay == null) continue
      const over = index > rules.maxTradesPerDay
      recordTradeCheck(
        "max_trades_per_day",
        trade,
        over ? "violated" : "followed",
        "trade",
        scopeFor(rules.maxTradesPerDayScope),
        over
          ? `Trade #${index} on ${trade.dayKey} exceeds cap ${rules.maxTradesPerDay}.`
          : `Trade #${index} on ${trade.dayKey} within cap ${rules.maxTradesPerDay}.`
      )
    }
  }

  for (const day of byLossDay.values()) {
    day.sort((a, b) => a.atMs - b.atMs)
    let running = 0
    let breached = false
    for (const trade of day) {
      const rules = rulesActiveAt(context, trade.atMs, trade.accountId)
      if (rules.dailyLossLimit == null) continue
      if (trade.pnl != null) running += trade.pnl
      if (!breached && running <= -rules.dailyLossLimit) {
        breached = true
        pushCheck(checks, {
          ruleId: "daily_loss_limit",
          outcome: "violated",
          level: "day",
          atMs: trade.atMs,
          dayKey: trade.dayKey,
          weekKey: trade.weekKey,
          monthKey: monthKeyFromDayKey(trade.dayKey),
          tradeId: trade.tradeId,
          accountId: trade.accountId,
          scopeLabel: scopeFor(rules.dailyLossLimitScope),
          detail: `Daily loss limit ${formatMoney(rules.dailyLossLimit)} crossed on ${trade.dayKey}.`,
          pnl: trade.pnl,
        })
        const bucket = impacts.get("daily_loss_limit")!
        addImpact(bucket.violated, trade.pnl)
        continue
      }
      if (breached) {
        recordTradeCheck(
          "daily_loss_limit",
          trade,
          "violated",
          "trade",
          scopeFor(rules.dailyLossLimitScope),
          `Trade after daily loss limit was crossed (${trade.dayKey}).`
        )
      }
    }
  }

  for (const day of byProfitDay.values()) {
    day.sort((a, b) => a.atMs - b.atMs)
    let running = 0
    let hit = false
    for (const trade of day) {
      const rules = rulesActiveAt(context, trade.atMs, trade.accountId)
      if (!rules.stopAfterDailyProfitTarget || rules.dailyProfitTarget == null) continue
      if (hit) {
        recordTradeCheck(
          "daily_profit_stop",
          trade,
          "violated",
          "trade",
          scopeFor(rules.dailyProfitRulesScope),
          `Trade after daily profit target (${formatMoney(rules.dailyProfitTarget)}) was reached.`
        )
      }
      if (trade.pnl != null) running += trade.pnl
      if (!hit && running >= rules.dailyProfitTarget) {
        hit = true
      }
    }
  }

  for (const week of byWeek.values()) {
    week.sort((a, b) => a.atMs - b.atMs)
    let running = 0
    let breached = false
    for (const trade of week) {
      const rules = rulesActiveAt(context, trade.atMs, trade.accountId)
      if (rules.maxWeeklyLoss == null) continue
      if (breached) {
        recordTradeCheck(
          "weekly_loss_limit",
          trade,
          "violated",
          "trade",
          scopeFor(rules.maxWeeklyLossScope),
          `Trade after weekly loss limit (${formatMoney(rules.maxWeeklyLoss)}) was crossed.`
        )
        continue
      }
      if (trade.pnl != null) running += trade.pnl
      if (running <= -rules.maxWeeklyLoss) {
        breached = true
        pushCheck(checks, {
          ruleId: "weekly_loss_limit",
          outcome: "violated",
          level: "week",
          atMs: trade.atMs,
          dayKey: trade.dayKey,
          weekKey: trade.weekKey,
          monthKey: monthKeyFromDayKey(trade.dayKey),
          tradeId: trade.tradeId,
          accountId: trade.accountId,
          scopeLabel: scopeFor(rules.maxWeeklyLossScope),
          detail: `Weekly loss limit ${formatMoney(rules.maxWeeklyLoss)} crossed (Eastern week ${trade.weekKey ?? "—"}).`,
          pnl: trade.pnl,
        })
        const bucket = impacts.get("weekly_loss_limit")!
        addImpact(bucket.violated, trade.pnl)
      }
    }
  }

  let unevaluated = 0
  for (const trade of ordered) {
    const rules = rulesActiveAt(context, trade.atMs, trade.accountId)
    if (rules.preferredSessions.length > 0 && !trade.session) unevaluated += 1
    if (rules.primaryInstruments.length > 0 && !trade.symbol) unevaluated += 1
    if (rules.plannedHours && trade.easternMinute == null) unevaluated += 1
    if (rules.allowedTradingDays.length > 0 && !trade.weekday) unevaluated += 1
    if (rules.minAcceptableRr != null && trade.plannedRr == null) unevaluated += 1
    if (rules.maxContractsPerTrade != null && trade.contracts == null) unevaluated += 1
    if (rules.maxRiskPerTrade != null && trade.dollarRisk == null) unevaluated += 1
    if (rules.targetRr != null && trade.maxRr == null) unevaluated += 1
  }

  let followed = 0
  let violated = 0
  for (const check of checks) {
    if (check.outcome === "followed") followed += 1
    else if (check.outcome === "violated") violated += 1
  }

  const evaluated = followed + violated
  const adherencePercent =
    evaluated > 0 ? Math.round((followed / evaluated) * 1000) / 10 : null

  const score: ComplianceScoreSummary = {
    adherencePercent,
    followed,
    violated,
    unevaluated,
    evaluated,
    explanation:
      "Adherence % = rules followed ÷ (followed + violations) among checks we could evaluate with reliable data. Unevaluated checks are excluded — never counted as compliant.",
  }

  const impactRows: RuleImpactRow[] = (Object.keys(RULE_LABELS) as RuleCheckId[]).map(
    (ruleId) => {
      const bucket = impacts.get(ruleId)!
      const sufficient =
        bucket.followed.priced >= COMPARATIVE_MIN_PER_SIDE &&
        bucket.violated.priced >= COMPARATIVE_MIN_PER_SIDE
      const wf = winRate(bucket.followed)
      const wv = winRate(bucket.violated)
      const af = avgPnl(bucket.followed)
      const av = avgPnl(bucket.violated)
      let summary: string | null = null
      if (sufficient && wf != null && wv != null && af != null && av != null) {
        summary = `When ${RULE_LABELS[ruleId].toLowerCase()} was followed, win rate was ${formatPct(wf)} with avg P&L ${formatMoney(af)} (${bucket.followed.priced} priced). When violated, win rate was ${formatPct(wv)} with avg P&L ${formatMoney(av)} (${bucket.violated.priced} priced). Correlation only — violations did not necessarily cause losses.`
      }
      return {
        ruleId,
        ruleLabel: RULE_LABELS[ruleId],
        followed: bucket.followed,
        violated: bucket.violated,
        sufficientSample: sufficient,
        winRateFollowed: wf,
        winRateViolated: wv,
        avgPnlFollowed: af,
        avgPnlViolated: av,
        summary,
      }
    }
  ).filter((row) => row.followed.priced + row.violated.priced > 0)

  const accountNames = options?.accountNames ?? {}
  const violations: RuleViolationEvent[] = checks
    .filter((c) => c.outcome === "violated")
    .sort((a, b) => b.atMs - a.atMs)
    .map((check) => ({
      id: check.id,
      atMs: check.atMs,
      dayKey: check.dayKey,
      tradeId: check.tradeId,
      accountId: check.accountId,
      accountLabel: check.accountId
        ? accountNames[check.accountId] ?? null
        : null,
      ruleId: check.ruleId,
      ruleLabel: check.ruleLabel,
      level: check.level,
      scopeLabel: check.scopeLabel,
      summary: check.detail,
    }))

  const weeklyTrend = buildTrend(
    checks,
    (row) => row.weekKey ?? row.dayKey,
    (key) => `Week of ${key}`,
    context,
    ordered
  )
  const monthlyTrend = buildTrend(
    checks,
    (row) => row.monthKey,
    (key) => key,
    context,
    ordered
  )

  return {
    score,
    impacts: impactRows,
    violations,
    weeklyTrend,
    monthlyTrend,
    usesHistoricalRevisions: (context?.revisions.length ?? 0) > 0,
  }
}

export function complianceTradesFromRows(
  rows: readonly Record<string, unknown>[]
): ComplianceTrade[] {
  return rows.flatMap((row) => {
    const mapped = complianceTradeFromRow(row)
    return mapped ? [mapped] : []
  })
}
