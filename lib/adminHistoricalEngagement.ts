import type { SupabaseClient } from "@supabase/supabase-js"
import type { DailyCountPoint } from "@/lib/adminAnalytics"
import { retentionRateLabel } from "@/lib/adminProductAnalytics"
import {
  type HistoricalEngagementQuery,
  validateHistoricalEngagementQuery,
} from "@/lib/adminHistoricalEngagementFilters"

export const HISTORICAL_ENGAGEMENT_DEFINITION =
  "Distinct users per UTC day with organic trade logging or social/messaging content created that day (created_at). Not app sessions."

export const HISTORICAL_EXECUTION_DATE_DEFINITION =
  "Counts of trades by trade_date (execution). Reflects journal market dates, not when users used the app."

export type HistoricalImportQuality = {
  manualEntered: number
  unsetImportSource: number
  csv: number
  broker: number
  other: number
  bulkInitialImportRows: number
  organicTradesLogged: number
  tradeDateBeforeCreatedDayRows: number
  nullTradeDateRows: number
}

export type AdminHistoricalEngagementBundle = {
  seriesDays: number
  meta: {
    notes: string[]
    isContentActivityNotSessions: boolean
    maxSeriesDays: number
    periodStart: string | null
    periodEnd: string | null
    rangeMode: string | null
    activityFilter: string | null
    retentionObservationEnd: string | null
  }
  overview: {
    engagedDau: number
    engagedWau: number
    engagedMau: number
    activeTradersDau: number
    activeCreatorsDau: number
    activeMessengersDau: number
    newSignupsInPeriod: number
    accountsCreatedInPeriod: number
  }
  growth: {
    signupsPerDay: DailyCountPoint[]
    accountsCreatedPerDay: DailyCountPoint[]
  }
  trading: {
    tradesLoggedPerDay: DailyCountPoint[]
    organicTradesLoggedPerDay: DailyCountPoint[]
    bulkImportTradesPerDay: DailyCountPoint[]
    tradesByExecutionDatePerDay: DailyCountPoint[]
    activeTradersPerDay: DailyCountPoint[]
    returningTradersPerDay: DailyCountPoint[]
    importQuality: HistoricalImportQuality
  }
  social: {
    postsPerDay: DailyCountPoint[]
    profilePostsPerDay: DailyCountPoint[]
    reelsPerDay: DailyCountPoint[]
    commentsPerDay: DailyCountPoint[]
    likesPerDay: DailyCountPoint[]
    followsPerDay: DailyCountPoint[]
    messagesPerDay: DailyCountPoint[]
    activeCreatorsPerDay: DailyCountPoint[]
    activeMessengersPerDay: DailyCountPoint[]
  }
  engagement: {
    engagedUsersPerDay: DailyCountPoint[]
    returningEngagedUsersPerDay: DailyCountPoint[]
    returningCreatorsPerDay: DailyCountPoint[]
  }
  retention: {
    d1Rate: number | null
    d7Rate: number | null
    d30Rate: number | null
    cohortSignupsTotal: number
    d1MatureCohortSize: number
    d7MatureCohortSize: number
    d30MatureCohortSize: number
    insufficientData: boolean
    definition: string
  }
}

export const HISTORICAL_SERIES_DAY_OPTIONS = [30, 90, 180, 365] as const
export type HistoricalSeriesDays = (typeof HISTORICAL_SERIES_DAY_OPTIONS)[number]

function num(v: unknown): number {
  if (typeof v === "number" && Number.isFinite(v)) return v
  if (typeof v === "string" && v.trim() !== "") {
    const n = Number(v)
    if (Number.isFinite(n)) return n
  }
  return 0
}

function numOrNull(v: unknown): number | null {
  if (v === null || v === undefined) return null
  if (typeof v === "number" && Number.isFinite(v)) return v
  if (typeof v === "string" && v.trim() !== "") {
    const n = Number(v)
    if (Number.isFinite(n)) return n
  }
  return null
}

function parseSeries(raw: unknown): DailyCountPoint[] {
  if (!Array.isArray(raw)) return []
  return raw.map((row) => {
    const o = row as Record<string, unknown>
    return {
      day: String(o.day ?? "").trim(),
      count: num(o.count),
    }
  })
}

function parseImportQuality(raw: Record<string, unknown>): HistoricalImportQuality {
  return {
    manualEntered: num(raw.manualEntered),
    unsetImportSource: num(raw.unsetImportSource),
    csv: num(raw.csv),
    broker: num(raw.broker),
    other: num(raw.other),
    bulkInitialImportRows: num(raw.bulkInitialImportRows),
    organicTradesLogged: num(raw.organicTradesLogged),
    tradeDateBeforeCreatedDayRows: num(raw.tradeDateBeforeCreatedDayRows),
    nullTradeDateRows: num(raw.nullTradeDateRows),
  }
}

function mapRpcToBundle(j: Record<string, unknown>): AdminHistoricalEngagementBundle {
  const meta = (j.meta ?? {}) as Record<string, unknown>
  const overview = (j.overview ?? {}) as Record<string, unknown>
  const growth = (j.growth ?? {}) as Record<string, unknown>
  const trading = (j.trading ?? {}) as Record<string, unknown>
  const social = (j.social ?? {}) as Record<string, unknown>
  const engagement = (j.engagement ?? {}) as Record<string, unknown>
  const retention = (j.retention ?? {}) as Record<string, unknown>
  const notesRaw = meta.notes
  const notes = Array.isArray(notesRaw) ? notesRaw.map((n) => String(n)) : []

  return {
    seriesDays: num(j.seriesDays),
    meta: {
      notes,
      isContentActivityNotSessions: meta.isContentActivityNotSessions === true,
      maxSeriesDays: num(meta.maxSeriesDays) || 365,
      periodStart: meta.periodStart != null ? String(meta.periodStart) : null,
      periodEnd: meta.periodEnd != null ? String(meta.periodEnd) : null,
      rangeMode: meta.rangeMode != null ? String(meta.rangeMode) : null,
      activityFilter: meta.activityFilter != null ? String(meta.activityFilter) : null,
      retentionObservationEnd:
        meta.retentionObservationEnd != null ? String(meta.retentionObservationEnd) : null,
    },
    overview: {
      engagedDau: num(overview.engagedDau),
      engagedWau: num(overview.engagedWau),
      engagedMau: num(overview.engagedMau),
      activeTradersDau: num(overview.activeTradersDau),
      activeCreatorsDau: num(overview.activeCreatorsDau),
      activeMessengersDau: num(overview.activeMessengersDau),
      newSignupsInPeriod: num(overview.newSignupsInPeriod),
      accountsCreatedInPeriod: num(overview.accountsCreatedInPeriod),
    },
    growth: {
      signupsPerDay: parseSeries(growth.signupsPerDay),
      accountsCreatedPerDay: parseSeries(growth.accountsCreatedPerDay),
    },
    trading: {
      tradesLoggedPerDay: parseSeries(trading.tradesLoggedPerDay),
      organicTradesLoggedPerDay: parseSeries(trading.organicTradesLoggedPerDay),
      bulkImportTradesPerDay: parseSeries(trading.bulkImportTradesPerDay),
      tradesByExecutionDatePerDay: parseSeries(trading.tradesByExecutionDatePerDay),
      activeTradersPerDay: parseSeries(trading.activeTradersPerDay),
      returningTradersPerDay: parseSeries(trading.returningTradersPerDay),
      importQuality: parseImportQuality((trading.importQuality ?? {}) as Record<string, unknown>),
    },
    social: {
      postsPerDay: parseSeries(social.postsPerDay),
      profilePostsPerDay: parseSeries(social.profilePostsPerDay),
      reelsPerDay: parseSeries(social.reelsPerDay),
      commentsPerDay: parseSeries(social.commentsPerDay),
      likesPerDay: parseSeries(social.likesPerDay),
      followsPerDay: parseSeries(social.followsPerDay),
      messagesPerDay: parseSeries(social.messagesPerDay),
      activeCreatorsPerDay: parseSeries(social.activeCreatorsPerDay),
      activeMessengersPerDay: parseSeries(social.activeMessengersPerDay),
    },
    engagement: {
      engagedUsersPerDay: parseSeries(engagement.engagedUsersPerDay),
      returningEngagedUsersPerDay: parseSeries(engagement.returningEngagedUsersPerDay),
      returningCreatorsPerDay: parseSeries(engagement.returningCreatorsPerDay),
    },
    retention: {
      d1Rate: numOrNull(retention.d1Rate),
      d7Rate: numOrNull(retention.d7Rate),
      d30Rate: numOrNull(retention.d30Rate),
      cohortSignupsTotal: num(retention.cohortSignupsTotal),
      d1MatureCohortSize: num(retention.d1MatureCohortSize),
      d7MatureCohortSize: num(retention.d7MatureCohortSize),
      d30MatureCohortSize: num(retention.d30MatureCohortSize),
      insufficientData: retention.insufficientData === true,
      definition: String(retention.definition ?? ""),
    },
  }
}

export async function fetchAdminHistoricalEngagementBundle(
  supabase: SupabaseClient,
  query: HistoricalEngagementQuery
): Promise<{ data: AdminHistoricalEngagementBundle | null; error: Error | null }> {
  const validation = validateHistoricalEngagementQuery(query)
  if (!validation.valid) {
    return { data: null, error: new Error(validation.message ?? "Invalid historical filters") }
  }

  const rpcArgs: Record<string, unknown> = {
    p_activity_filter: query.activityFilter,
  }

  if (query.preset === "custom") {
    rpcArgs.p_series_days = null
    rpcArgs.p_start_date = query.customStartDate
    rpcArgs.p_end_date = query.customEndDate
  } else {
    rpcArgs.p_series_days = Math.max(1, Math.min(365, query.preset))
    rpcArgs.p_start_date = null
    rpcArgs.p_end_date = null
  }

  const { data, error } = await supabase.rpc("admin_historical_engagement_bundle", rpcArgs)

  if (error) {
    return { data: null, error: new Error(error.message) }
  }

  let parsed: unknown = data
  if (typeof data === "string") {
    try {
      parsed = JSON.parse(data)
    } catch {
      return { data: null, error: new Error("Invalid historical engagement response (JSON parse failed)") }
    }
  }

  const j = parsed as Record<string, unknown> | null
  if (!j || typeof j !== "object" || Array.isArray(j)) {
    return { data: null, error: new Error("Invalid historical engagement response") }
  }

  return { data: mapRpcToBundle(j), error: null }
}

export function historicalRetentionRateLabel(
  rate: number | null | undefined,
  matureCohortSize: number,
  insufficientData: boolean
): string {
  return retentionRateLabel(rate, matureCohortSize, insufficientData)
}

export function sumSeriesCounts(points: DailyCountPoint[]): number {
  return points.reduce((acc, p) => acc + (Number.isFinite(p.count) ? p.count : 0), 0)
}