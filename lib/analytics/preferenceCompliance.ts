import { COMPARATIVE_MIN_PER_SIDE, knownPnl } from "@/lib/analytics/knownPnl"
import {
  emptyResolvedTradingPreferences,
  resolveTradingPreferences,
  tradingPreferencesActiveAt,
  type ResolvedTradingPreferences,
  type TradingPreferenceAccountOverride,
  type TradingPreferenceGlobal,
  type TradingPreferenceRevision,
} from "@/lib/analytics/tradingPreferences"
import {
  easternWeekdayFromInstant,
  easternWeekKeyFromInstant,
  scopedDayBucket,
  scopedWeekBucket,
  scopeBucketLabel,
  weekdayDisplayLabel,
  type TradingRuleWeekday,
} from "@/lib/analytics/tradingRuleScope"
import { psychologyTradeDateKey } from "@/lib/psychology/tradeDateKey"

/**
 * Historical personal-rule checks shared by dashboard, reports, and scorecard.
 * A blank preference is not a rule. Missing P&L stays out of averages.
 */
export type PreferenceRuleContext = {
  revisions: readonly TradingPreferenceRevision[]
  global: TradingPreferenceGlobal | null
  overrides: readonly TradingPreferenceAccountOverride[]
}

export type ComplianceTrade = {
  tradeId: string | null
  atMs: number
  accountId: string | null
  session: string | null
  symbol: string | null
  pnl: number | null
  easternMinute: number | null
  dayKey: string
  weekKey: string | null
  weekday: TradingRuleWeekday | null
  maxRr: number | null
  plannedRr: number | null
  contracts: number | null
  dollarRisk: number | null
}

type Side = {
  trades: number
  priced: number
  net: number
}

export type PreferenceCompliance = {
  usesHistory: boolean
  sessionActive: boolean
  inSession: Side
  outsideSession: Side
  instrumentsActive: boolean
  inInstruments: Side
  outsideInstruments: Side
  hoursActive: boolean
  inHours: Side
  outsideHours: Side
  rulesActive: boolean
  ruleFamilies: number
  insideRules: Side
  outsideRules: Side
  capActive: boolean
  overCapDays: number
  overCap: Side
  withinCap: Side
  lossLimitActive: boolean
  lossLimitDays: number
  afterBreach: Side
  targetPaired: number
  uniformTargetRr: number | null
  avgMaxRr: number | null
  shortOfTarget: number
  minRrActive: boolean
  belowMinRr: Side
  withinMinRr: Side
  minRrPaired: number
  allowedDaysActive: boolean
  outsideAllowedDays: Side
  withinAllowedDays: Side
  maxContractsActive: boolean
  overMaxContracts: Side
  withinMaxContracts: Side
  maxRiskActive: boolean
  maxRiskPaired: number
  overMaxRisk: Side
  withinMaxRisk: Side
  weeklyLossActive: boolean
  weeklyLossScopeLabel: string | null
  weeklyLossWeeks: number
  afterWeeklyLossBreach: Side
  profitStopActive: boolean
  profitStopScopeLabel: string | null
  afterProfitTarget: Side
  capScopeLabel: string | null
  lossLimitScopeLabel: string | null
}

export type PsychologyRuleSnapshot = {
  consecutiveLossPause: number | null
  maxTradesPerDay: number | null
  waitAfterLossMinutes: number | null
}

const EMPTY_PSYCHOLOGY_RULES: PsychologyRuleSnapshot = {
  consecutiveLossPause: null,
  maxTradesPerDay: null,
  waitAfterLossMinutes: null,
}

function emptySide(): Side {
  return { trades: 0, priced: 0, net: 0 }
}

function add(side: Side, pnl: number | null) {
  side.trades += 1
  if (pnl == null) return
  side.priced += 1
  side.net += pnl
}

function avg(side: Side): number | null {
  return side.priced > 0 ? side.net / side.priced : null
}

export function formatComplianceMoney(value: number): string {
  const abs = Math.abs(value).toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
  return value < 0 ? `-$${abs}` : `$${abs}`
}

export function formatComplianceR(value: number): string {
  const rounded = Math.round(value * 10) / 10
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1)
}

function canonicalSession(raw: string | null | undefined): string | null {
  const value = String(raw ?? "").trim().toLowerCase()
  if (!value) return null
  if (value === "ny am" || value === "new york am") return "NY AM"
  if (value === "ny lunch" || value === "new york lunch" || value === "lunch") return "NY Lunch"
  if (value === "ny pm" || value === "new york pm" || value === "pm") return "NY PM"
  if (value === "london" || value === "ldn" || value === "uk") return "London"
  if (value === "asia" || value === "asian" || value === "tokyo") return "Asia"
  if (value === "after") return "After"
  if (value.includes("lunch") && (value.includes("ny") || value.includes("new york"))) return "NY Lunch"
  if (value.includes("pm") && (value.includes("ny") || value.includes("new york"))) return "NY PM"
  if (value.includes("am") && (value.includes("ny") || value.includes("new york"))) return "NY AM"
  if (value === "ny" || value === "new york" || (value.includes("ny") && !value.includes("london"))) {
    return "NY AM"
  }
  return null
}

export function easternMinuteOfDay(instant: Date): number | null {
  if (Number.isNaN(instant.getTime())) return null
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/New_York",
    hour: "numeric",
    minute: "numeric",
    hourCycle: "h23",
  }).formatToParts(instant)
  const hour = Number(parts.find((part) => part.type === "hour")?.value)
  const minute = Number(parts.find((part) => part.type === "minute")?.value)
  if (!Number.isFinite(hour) || !Number.isFinite(minute)) return null
  const normalized = hour === 24 ? 0 : hour
  return normalized * 60 + minute
}

function minuteInWindow(minute: number, start: number, end: number): boolean {
  if (end > start) return minute >= start && minute < end
  return minute >= start || minute < end
}

export function rulesActiveAt(
  context: PreferenceRuleContext | null | undefined,
  atMs: number,
  accountId: string | null
): ResolvedTradingPreferences {
  if (!context) return emptyResolvedTradingPreferences()
  if (context.revisions.length > 0) {
    return tradingPreferencesActiveAt(context.revisions, new Date(atMs), accountId)
  }
  if (!context.global) return emptyResolvedTradingPreferences()
  const override =
    context.overrides.find((row) => row.accountId === accountId) ?? null
  return resolveTradingPreferences(context.global, override)
}

export function psychologyRulesAt(
  context: PreferenceRuleContext | null | undefined,
  atMs: number
): PsychologyRuleSnapshot {
  const rules = rulesActiveAt(context, atMs, null)
  return {
    consecutiveLossPause: rules.consecutiveLossPause,
    maxTradesPerDay: rules.maxTradesPerDay,
    waitAfterLossMinutes: rules.waitAfterLossMinutes,
  }
}

export function currentPsychologyRules(
  context: PreferenceRuleContext | null | undefined
): PsychologyRuleSnapshot {
  if (!context) return EMPTY_PSYCHOLOGY_RULES
  if (context.revisions.length > 0) {
    const latest = [...context.revisions].sort(
      (a, b) => Date.parse(a.effectiveFrom) - Date.parse(b.effectiveFrom)
    )
    const row = latest[latest.length - 1]
    if (!row) return EMPTY_PSYCHOLOGY_RULES
    return psychologyRulesAt(context, Date.parse(row.effectiveFrom))
  }
  return {
    consecutiveLossPause: context.global?.consecutiveLossPause ?? null,
    maxTradesPerDay: context.global?.maxTradesPerDay ?? null,
    waitAfterLossMinutes: context.global?.waitAfterLossMinutes ?? null,
  }
}

function finiteNumber(value: unknown): number | null {
  const n = knownPnl(value)
  return n
}

export function complianceTradeFromRow(row: {
  entry_time?: string | null
  created_at?: string | null
  trade_date?: string | null
  date?: string | null
  session?: string | null
  ticker?: string | null
  symbol?: string | null
  pnl?: unknown
  account_id?: string | null
  max_rr_reached?: unknown
  rr?: unknown
  contracts?: unknown
  dollar_risk?: unknown
}): ComplianceTrade | null {
  const entry = String(row.entry_time ?? row.created_at ?? "").trim()
  const at = entry ? new Date(entry) : null
  if (!at || Number.isNaN(at.getTime())) return null
  const dayKey = psychologyTradeDateKey({
    entry_time: row.entry_time,
    created_at: row.created_at,
    trade_date: row.trade_date,
    date: row.date,
  })
  if (!dayKey) return null
  const symbol = String(row.ticker ?? row.symbol ?? "").trim()
  const contractsRaw = finiteNumber(row.contracts)
  const contracts =
    contractsRaw != null && Number.isInteger(contractsRaw) && contractsRaw > 0
      ? contractsRaw
      : null
  const plannedRrRaw = finiteNumber(row.rr)
  const plannedRr = plannedRrRaw != null && plannedRrRaw > 0 ? plannedRrRaw : null
  const dollarRiskRaw = finiteNumber(row.dollar_risk)
  const dollarRisk = dollarRiskRaw != null && dollarRiskRaw > 0 ? dollarRiskRaw : null
  const tradeId = (row as { id?: unknown }).id
  return {
    tradeId:
      tradeId != null && String(tradeId).trim() !== ""
        ? String(tradeId)
        : null,
    atMs: at.getTime(),
    accountId: row.account_id ? String(row.account_id) : null,
    session: canonicalSession(row.session),
    symbol: symbol ? symbol.toUpperCase() : null,
    pnl: finiteNumber(row.pnl),
    easternMinute: easternMinuteOfDay(at),
    dayKey,
    weekKey: easternWeekKeyFromInstant(at),
    weekday: easternWeekdayFromInstant(at),
    maxRr: finiteNumber(row.max_rr_reached),
    plannedRr,
    contracts,
    dollarRisk,
  }
}

export function evaluatePreferenceCompliance(
  trades: readonly ComplianceTrade[],
  context: PreferenceRuleContext | null | undefined
): PreferenceCompliance {
  const summary: PreferenceCompliance = {
    usesHistory: (context?.revisions.length ?? 0) > 0,
    sessionActive: false,
    inSession: emptySide(),
    outsideSession: emptySide(),
    instrumentsActive: false,
    inInstruments: emptySide(),
    outsideInstruments: emptySide(),
    hoursActive: false,
    inHours: emptySide(),
    outsideHours: emptySide(),
    rulesActive: false,
    ruleFamilies: 0,
    insideRules: emptySide(),
    outsideRules: emptySide(),
    capActive: false,
    overCapDays: 0,
    overCap: emptySide(),
    withinCap: emptySide(),
    lossLimitActive: false,
    lossLimitDays: 0,
    afterBreach: emptySide(),
    targetPaired: 0,
    uniformTargetRr: null,
    avgMaxRr: null,
    shortOfTarget: 0,
    minRrActive: false,
    belowMinRr: emptySide(),
    withinMinRr: emptySide(),
    minRrPaired: 0,
    allowedDaysActive: false,
    outsideAllowedDays: emptySide(),
    withinAllowedDays: emptySide(),
    maxContractsActive: false,
    overMaxContracts: emptySide(),
    withinMaxContracts: emptySide(),
    maxRiskActive: false,
    maxRiskPaired: 0,
    overMaxRisk: emptySide(),
    withinMaxRisk: emptySide(),
    weeklyLossActive: false,
    weeklyLossScopeLabel: null,
    weeklyLossWeeks: 0,
    afterWeeklyLossBreach: emptySide(),
    profitStopActive: false,
    profitStopScopeLabel: null,
    afterProfitTarget: emptySide(),
    capScopeLabel: null,
    lossLimitScopeLabel: null,
  }
  if (!context) return summary

  const ordered = [...trades].sort((a, b) => a.atMs - b.atMs)
  const byCapDayBucket = new Map<string, ComplianceTrade[]>()
  const byLossDayBucket = new Map<string, ComplianceTrade[]>()
  const byProfitDayBucket = new Map<string, ComplianceTrade[]>()
  const byWeekBucket = new Map<string, ComplianceTrade[]>()
  const targets = new Set<number>()
  let maxSum = 0

  for (const trade of ordered) {
    const rules = rulesActiveAt(context, trade.atMs, trade.accountId)
    const families: boolean[] = []
    let violated = false

    if (rules.preferredSessions.length > 0 && trade.session) {
      summary.sessionActive = true
      const inside = rules.preferredSessions.includes(
        trade.session as (typeof rules.preferredSessions)[number]
      )
      add(inside ? summary.inSession : summary.outsideSession, trade.pnl)
      families.push(true)
      if (!inside) violated = true
    }

    if (rules.primaryInstruments.length > 0 && trade.symbol) {
      summary.instrumentsActive = true
      const inside = rules.primaryInstruments.includes(trade.symbol)
      add(inside ? summary.inInstruments : summary.outsideInstruments, trade.pnl)
      families.push(true)
      if (!inside) violated = true
    }

    if (rules.plannedHours && trade.easternMinute != null) {
      summary.hoursActive = true
      const inside = minuteInWindow(
        trade.easternMinute,
        rules.plannedHours.startMinute,
        rules.plannedHours.endMinute
      )
      add(inside ? summary.inHours : summary.outsideHours, trade.pnl)
      families.push(true)
      if (!inside) violated = true
    }

    if (families.length > 0) {
      summary.rulesActive = true
      add(violated ? summary.outsideRules : summary.insideRules, trade.pnl)
    }

    if (rules.targetRr != null && trade.maxRr != null) {
      summary.targetPaired += 1
      maxSum += trade.maxRr
      targets.add(rules.targetRr)
      if (trade.maxRr < rules.targetRr) summary.shortOfTarget += 1
    }

    if (rules.minAcceptableRr != null) {
      summary.minRrActive = true
      if (trade.plannedRr != null) {
        summary.minRrPaired += 1
        if (trade.plannedRr < rules.minAcceptableRr) {
          add(summary.belowMinRr, trade.pnl)
        } else {
          add(summary.withinMinRr, trade.pnl)
        }
      }
    }

    if (rules.allowedTradingDays.length > 0 && trade.weekday) {
      summary.allowedDaysActive = true
      const inside = rules.allowedTradingDays.includes(trade.weekday)
      add(inside ? summary.withinAllowedDays : summary.outsideAllowedDays, trade.pnl)
    }

    if (rules.maxContractsPerTrade != null) {
      summary.maxContractsActive = true
      if (trade.contracts != null) {
        if (trade.contracts > rules.maxContractsPerTrade) {
          add(summary.overMaxContracts, trade.pnl)
        } else {
          add(summary.withinMaxContracts, trade.pnl)
        }
      }
    }

    if (rules.maxRiskPerTrade != null) {
      summary.maxRiskActive = true
      if (trade.dollarRisk != null) {
        summary.maxRiskPaired += 1
        if (trade.dollarRisk > rules.maxRiskPerTrade) {
          add(summary.overMaxRisk, trade.pnl)
        } else {
          add(summary.withinMaxRisk, trade.pnl)
        }
      }
    }

    if (trade.weekKey) {
      const rulesAtTrade = rulesActiveAt(context, trade.atMs, trade.accountId)
      const weekBucket = scopedWeekBucket(
        trade.weekKey,
        trade.accountId,
        rulesAtTrade.maxWeeklyLossScope
      )
      const weekList = byWeekBucket.get(weekBucket) ?? []
      weekList.push(trade)
      byWeekBucket.set(weekBucket, weekList)
    }

    const capRules = rulesActiveAt(context, trade.atMs, trade.accountId)
    summary.capScopeLabel ??= scopeBucketLabel(capRules.maxTradesPerDayScope)
    summary.lossLimitScopeLabel ??= scopeBucketLabel(capRules.dailyLossLimitScope)
    summary.profitStopScopeLabel ??= scopeBucketLabel(capRules.dailyProfitRulesScope)
    summary.weeklyLossScopeLabel ??= scopeBucketLabel(capRules.maxWeeklyLossScope)

    const capKey = scopedDayBucket(trade.dayKey, trade.accountId, capRules.maxTradesPerDayScope)
    const capList = byCapDayBucket.get(capKey) ?? []
    capList.push(trade)
    byCapDayBucket.set(capKey, capList)

    const lossKey = scopedDayBucket(trade.dayKey, trade.accountId, capRules.dailyLossLimitScope)
    const lossList = byLossDayBucket.get(lossKey) ?? []
    lossList.push(trade)
    byLossDayBucket.set(lossKey, lossList)

    const profitKey = scopedDayBucket(
      trade.dayKey,
      trade.accountId,
      capRules.dailyProfitRulesScope
    )
    const profitList = byProfitDayBucket.get(profitKey) ?? []
    profitList.push(trade)
    byProfitDayBucket.set(profitKey, profitList)
  }

  summary.ruleFamilies =
    Number(summary.sessionActive) +
    Number(summary.instrumentsActive) +
    Number(summary.hoursActive)
  if (summary.targetPaired > 0) {
    summary.avgMaxRr = maxSum / summary.targetPaired
    summary.uniformTargetRr = targets.size === 1 ? [...targets][0]! : null
  }

  for (const day of byCapDayBucket.values()) {
    day.sort((a, b) => a.atMs - b.atMs)
    let index = 0
    let dayOverCap = false
    for (const trade of day) {
      index += 1
      const rules = rulesActiveAt(context, trade.atMs, trade.accountId)
      if (rules.maxTradesPerDay == null) continue
      summary.capActive = true
      const over = index > rules.maxTradesPerDay
      add(over ? summary.overCap : summary.withinCap, trade.pnl)
      if (over) dayOverCap = true
    }
    if (dayOverCap) summary.overCapDays += 1
  }

  for (const day of byLossDayBucket.values()) {
    day.sort((a, b) => a.atMs - b.atMs)
    let running = 0
    let breached = false
    for (const trade of day) {
      const rules = rulesActiveAt(context, trade.atMs, trade.accountId)
      if (rules.dailyLossLimit == null) continue
      summary.lossLimitActive = true
      if (trade.pnl != null) running += trade.pnl
      if (!breached && running <= -rules.dailyLossLimit) {
        breached = true
        continue
      }
      if (breached) add(summary.afterBreach, trade.pnl)
    }
    if (breached) summary.lossLimitDays += 1
  }

  for (const day of byProfitDayBucket.values()) {
    day.sort((a, b) => a.atMs - b.atMs)
    let running = 0
    let profitThresholdReached = false
    for (const trade of day) {
      const rules = rulesActiveAt(context, trade.atMs, trade.accountId)
      if (!rules.stopAfterDailyProfitTarget || rules.dailyProfitTarget == null) continue
      summary.profitStopActive = true
      if (profitThresholdReached) {
        add(summary.afterProfitTarget, trade.pnl)
      }
      if (trade.pnl != null) running += trade.pnl
      if (!profitThresholdReached && running >= rules.dailyProfitTarget) {
        profitThresholdReached = true
      }
    }
  }

  for (const week of byWeekBucket.values()) {
    week.sort((a, b) => a.atMs - b.atMs)
    let running = 0
    let breached = false
    for (const trade of week) {
      const rules = rulesActiveAt(context, trade.atMs, trade.accountId)
      if (rules.maxWeeklyLoss == null) continue
      summary.weeklyLossActive = true
      if (breached) {
        add(summary.afterWeeklyLossBreach, trade.pnl)
        continue
      }
      if (trade.pnl != null) running += trade.pnl
      if (running <= -rules.maxWeeklyLoss) {
        breached = true
        summary.weeklyLossWeeks += 1
      }
    }
  }

  return summary
}

function bothSides(left: Side, right: Side): boolean {
  return left.priced >= COMPARATIVE_MIN_PER_SIDE && right.priced >= COMPARATIVE_MIN_PER_SIDE
}

function compareLine(insideLabel: string, inside: Side, outsideLabel: string, outside: Side): string | null {
  if (!bothSides(inside, outside)) return null
  const insideAvg = avg(inside)
  const outsideAvg = avg(outside)
  if (insideAvg == null || outsideAvg == null) return null
  return `${insideLabel} averaged ${formatComplianceMoney(insideAvg)} (${inside.priced} priced). ${outsideLabel} averaged ${formatComplianceMoney(outsideAvg)} (${outside.priced} priced).`
}

export function preferenceComplianceLines(summary: PreferenceCompliance): string[] {
  const lines: string[] = []
  const sessionTotal = summary.inSession.trades + summary.outsideSession.trades
  if (summary.sessionActive && summary.outsideSession.trades > 0) {
    lines.push(
      `${summary.outsideSession.trades} of ${sessionTotal} trades were outside your preferred sessions.`
    )
  }
  const instrumentTotal = summary.inInstruments.trades + summary.outsideInstruments.trades
  if (summary.instrumentsActive && summary.outsideInstruments.trades > 0) {
    lines.push(
      `${summary.outsideInstruments.trades} of ${instrumentTotal} trades were outside your primary instruments.`
    )
  }
  const hourTotal = summary.inHours.trades + summary.outsideHours.trades
  if (summary.hoursActive && summary.outsideHours.trades > 0) {
    lines.push(
      `${summary.outsideHours.trades} of ${hourTotal} trades were outside your planned trading hours.`
    )
  }
  if (summary.capActive && summary.overCap.trades > 0) {
    const trades =
      summary.overCap.trades === 1 ? "1 trade was" : `${summary.overCap.trades} trades were`
    const days = summary.overCapDays === 1 ? "1 day" : `${summary.overCapDays} days`
    const scope =
      summary.capScopeLabel != null ? ` (${summary.capScopeLabel})` : ""
    lines.push(`${trades} beyond your daily trade cap${scope}, across ${days}.`)
  }
  if (summary.lossLimitActive && summary.lossLimitDays > 0) {
    const scope =
      summary.lossLimitScopeLabel != null ? ` (${summary.lossLimitScopeLabel})` : ""
    lines.push(
      summary.lossLimitDays === 1
        ? `1 day crossed your daily loss limit${scope}.`
        : `${summary.lossLimitDays} days crossed your daily loss limit${scope}.`
    )
  }
  if (summary.profitStopActive && summary.afterProfitTarget.trades > 0) {
    const scope =
      summary.profitStopScopeLabel != null ? ` (${summary.profitStopScopeLabel})` : ""
    const trades =
      summary.afterProfitTarget.trades === 1
        ? "1 trade was"
        : `${summary.afterProfitTarget.trades} trades were`
    lines.push(
      `${trades} taken after your daily profit target was reached${scope}, not including the trade that first hit the target.`
    )
  }
  if (summary.weeklyLossActive && summary.weeklyLossWeeks > 0) {
    const scope =
      summary.weeklyLossScopeLabel != null ? ` (${summary.weeklyLossScopeLabel})` : ""
    lines.push(
      summary.weeklyLossWeeks === 1
        ? `1 Eastern week crossed your weekly loss limit${scope}.`
        : `${summary.weeklyLossWeeks} Eastern weeks crossed your weekly loss limit${scope}.`
    )
  }
  if (summary.allowedDaysActive && summary.outsideAllowedDays.trades > 0) {
  const total = summary.outsideAllowedDays.trades + summary.withinAllowedDays.trades
    lines.push(
      `${summary.outsideAllowedDays.trades} of ${total} trades fell on days outside your allowed trading days.`
    )
  }
  if (summary.maxContractsActive && summary.overMaxContracts.trades > 0) {
    const trades =
      summary.overMaxContracts.trades === 1
        ? "1 trade exceeded"
        : `${summary.overMaxContracts.trades} trades exceeded`
    lines.push(`${trades} your maximum contracts-per-trade limit (trades with a recorded contract size).`)
  }
  if (summary.minRrActive && summary.minRrPaired > 0 && summary.belowMinRr.trades > 0) {
    lines.push(
      `${summary.belowMinRr.trades} of ${summary.minRrPaired} trades with a planned R:R were below your minimum acceptable R:R.`
    )
  }
  if (summary.maxRiskActive) {
    if (summary.maxRiskPaired === 0) {
      lines.push(
        "Maximum risk per trade is set, but none of your trades in this period recorded dollar risk at entry."
      )
    } else if (summary.overMaxRisk.trades > 0) {
      const trades =
        summary.overMaxRisk.trades === 1 ? "1 trade exceeded" : `${summary.overMaxRisk.trades} trades exceeded`
      lines.push(
        `${trades} your maximum risk per trade among ${summary.maxRiskPaired} trades with recorded dollar risk.`
      )
    }
  }

  if (summary.ruleFamilies >= 2) {
    const combined = compareLine(
      "Trades inside your personal rules",
      summary.insideRules,
      "Trades outside them",
      summary.outsideRules
    )
    if (combined) lines.push(combined)
  } else {
    const session = compareLine(
      "Inside your preferred sessions",
      summary.inSession,
      "Outside those sessions",
      summary.outsideSession
    )
    if (session) lines.push(session)
    const instruments = compareLine(
      "Trades in your primary instruments",
      summary.inInstruments,
      "Outside those instruments",
      summary.outsideInstruments
    )
    if (instruments) lines.push(instruments)
    const hours = compareLine(
      "Trades inside your planned hours",
      summary.inHours,
      "Outside those hours",
      summary.outsideHours
    )
    if (hours) lines.push(hours)
  }

  const cap = compareLine(
    "Trades within your daily cap",
    summary.withinCap,
    "Trades beyond it",
    summary.overCap
  )
  if (cap) lines.push(cap)

  if (summary.afterBreach.priced >= COMPARATIVE_MIN_PER_SIDE) {
    const after = avg(summary.afterBreach)
    if (after != null) {
      lines.push(
        `After the daily loss limit was crossed, the next priced trades averaged ${formatComplianceMoney(after)} (${summary.afterBreach.priced} trades).`
      )
    }
  }

  if (
    summary.uniformTargetRr != null &&
    summary.avgMaxRr != null &&
    summary.targetPaired >= COMPARATIVE_MIN_PER_SIDE
  ) {
    const maxLabel = formatComplianceR(summary.avgMaxRr)
    const targetLabel = formatComplianceR(summary.uniformTargetRr)
    lines.push(
      summary.avgMaxRr < summary.uniformTargetRr
        ? `Average max R was ${maxLabel}, short of your ${targetLabel}R target, across ${summary.targetPaired} trades.`
        : `Average max R was ${maxLabel} versus your ${targetLabel}R target, across ${summary.targetPaired} trades.`
    )
  }

  return lines
}

function worse(left: Side, right: Side): boolean {
  if (!bothSides(left, right)) return false
  const a = avg(left)
  const b = avg(right)
  return a != null && b != null && b < a
}

/** One evidence-backed report adjustment. Activity counts alone do not qualify. */
export function primaryRuleAdjustment(summary: PreferenceCompliance): string | null {
  if (summary.ruleFamilies >= 2 && worse(summary.insideRules, summary.outsideRules)) {
    return compareLine(
      "Trades inside your personal rules",
      summary.insideRules,
      "Trades outside them",
      summary.outsideRules
    )
  }
  if (worse(summary.inSession, summary.outsideSession)) {
    return compareLine(
      "Inside your preferred sessions",
      summary.inSession,
      "Outside those sessions",
      summary.outsideSession
    )
  }
  if (worse(summary.inHours, summary.outsideHours)) {
    return compareLine(
      "Trades inside your planned hours",
      summary.inHours,
      "Outside those hours",
      summary.outsideHours
    )
  }
  if (worse(summary.inInstruments, summary.outsideInstruments)) {
    return compareLine(
      "Trades in your primary instruments",
      summary.inInstruments,
      "Outside those instruments",
      summary.outsideInstruments
    )
  }
  if (worse(summary.withinCap, summary.overCap)) {
    return compareLine(
      "Trades within your daily cap",
      summary.withinCap,
      "Trades beyond it",
      summary.overCap
    )
  }
  if (summary.afterBreach.priced >= COMPARATIVE_MIN_PER_SIDE) {
    const after = avg(summary.afterBreach)
    if (after != null) {
      return `After the daily loss limit was crossed, the next priced trades averaged ${formatComplianceMoney(after)} (${summary.afterBreach.priced} trades).`
    }
  }
  if (
    summary.uniformTargetRr != null &&
    summary.avgMaxRr != null &&
    summary.avgMaxRr < summary.uniformTargetRr &&
    summary.targetPaired >= COMPARATIVE_MIN_PER_SIDE
  ) {
    return `Average max R was ${formatComplianceR(summary.avgMaxRr)}, short of your ${formatComplianceR(summary.uniformTargetRr)}R target, across ${summary.targetPaired} trades.`
  }
  return null
}

export function preferenceFingerprint(context: PreferenceRuleContext | null | undefined): string {
  if (!context) return "noprefs"
  const latest = context.revisions[context.revisions.length - 1]?.effectiveFrom ?? ""
  return `${context.revisions.length}:${latest}:${context.global?.updatedAt ?? ""}:${context.overrides.length}`
}
