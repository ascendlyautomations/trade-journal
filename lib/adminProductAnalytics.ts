import type { SupabaseClient } from "@supabase/supabase-js"
import type { DailyCountPoint } from "@/lib/adminAnalytics"

export const PRODUCT_DAU_DEFINITION =
  "Distinct users per UTC day with product engagement (session or app open rollups). Excludes broker background sync."

export const LEGACY_ACTIVITY_DAU_DEFINITION =
  "Legacy metric: distinct users who created trades, posts, stories, feedback, or support tickets in a rolling window — not product sessions."

/** Product DAU series may use null count before tracking start. */
export type ProductDailyCountPoint = { day: string; count: number | null }

export type AdminProductFeatureRow = {
  feature: string
  uniqueUsers: number
  webUniqueUsers: number
  iosUniqueUsers: number
  useCount: number
}

export type AdminProductImportTotals = {
  manualEntered: number
  unsetImportSource: number
  csv: number
  broker: number
  other: number
}

export type AdminProductAnalyticsBundle = {
  seriesDays: number
  meta: {
    productTrackingStartDate: string | null
    productEngagementAvailable: boolean
    retentionMetricsAvailable: boolean
    previewFunnelAvailable: boolean
    notes: string[]
  }
  overview: {
    totalUsers: number
    newSignupsToday: number
    productDau: number | null
    productWau: number | null
    productMau: number | null
    dauMauRatio: number | null
  }
  growth: {
    signupsPerDay: DailyCountPoint[]
    productActiveUsersPerDay: ProductDailyCountPoint[]
  }
  retention: {
    d1Rate: number | null
    d7Rate: number | null
    d30Rate: number | null
    returningUsersPerDay: DailyCountPoint[]
    cohortSampleSignups: number
    d1MatureCohortSize: number
    d7MatureCohortSize: number
    d30MatureCohortSize: number
    insufficientData: boolean
  }
  trading: {
    tradesCreatedPerDay: DailyCountPoint[]
    activeTradersPerDay: DailyCountPoint[]
    tradesPerActiveTraderLatestDay: number | null
    importTotalsInPeriod: AdminProductImportTotals
  }
  social: {
    profileViewsPerDay: DailyCountPoint[]
    uniqueProfileViewersPerDay: DailyCountPoint[]
    postsPerDay: DailyCountPoint[]
    featureEngagementPerDay: DailyCountPoint[]
  }
  features: {
    topFeatures: AdminProductFeatureRow[]
  }
  traxsProPreview: {
    available: boolean
    startsPerDay: DailyCountPoint[]
    exitsPerDay: DailyCountPoint[]
    upgradeTapsPerDay: DailyCountPoint[]
    funnelTotals: {
      starts: number
      exits: number
      upgradeTaps: number
      startToUpgradeRate: number | null
    }
  }
}

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
    const count = o.count
    return {
      day: String(o.day ?? "").trim(),
      count: count === null || count === undefined ? 0 : num(count),
    }
  })
}

function parseProductActiveSeries(raw: unknown): ProductDailyCountPoint[] {
  if (!Array.isArray(raw)) return []
  return raw.map((row) => {
    const o = row as Record<string, unknown>
    const count = o.count
    return {
      day: String(o.day ?? "").trim(),
      count: count === null || count === undefined ? null : num(count),
    }
  })
}

function parseImportTotals(raw: Record<string, unknown>): AdminProductImportTotals {
  const legacyManual = num(raw.manual)
  return {
    manualEntered: num(raw.manualEntered) || (legacyManual > 0 ? legacyManual : 0),
    unsetImportSource: num(raw.unsetImportSource),
    csv: num(raw.csv),
    broker: num(raw.broker),
    other: num(raw.other),
  }
}

function parseFeatureRows(raw: unknown): AdminProductFeatureRow[] {
  if (!Array.isArray(raw)) return []
  return raw.map((row) => {
    const o = row as Record<string, unknown>
    return {
      feature: String(o.feature ?? ""),
      uniqueUsers: num(o.uniqueUsers),
      webUniqueUsers: num(o.webUniqueUsers),
      iosUniqueUsers: num(o.iosUniqueUsers),
      useCount: num(o.useCount),
    }
  })
}

function mapRpcToBundle(j: Record<string, unknown>): AdminProductAnalyticsBundle {
  const meta = (j.meta ?? {}) as Record<string, unknown>
  const overview = (j.overview ?? {}) as Record<string, unknown>
  const growth = (j.growth ?? {}) as Record<string, unknown>
  const retention = (j.retention ?? {}) as Record<string, unknown>
  const trading = (j.trading ?? {}) as Record<string, unknown>
  const social = (j.social ?? {}) as Record<string, unknown>
  const features = (j.features ?? {}) as Record<string, unknown>
  const preview = (j.traxsProPreview ?? {}) as Record<string, unknown>
  const funnel = (preview.funnelTotals ?? {}) as Record<string, unknown>
  const imports = (trading.importTotalsInPeriod ?? {}) as Record<string, unknown>
  const notesRaw = meta.notes
  const notes = Array.isArray(notesRaw) ? notesRaw.map((n) => String(n)) : []

  return {
    seriesDays: num(j.seriesDays),
    meta: {
      productTrackingStartDate:
        meta.productTrackingStartDate != null ? String(meta.productTrackingStartDate) : null,
      productEngagementAvailable: meta.productEngagementAvailable === true,
      retentionMetricsAvailable: meta.retentionMetricsAvailable === true,
      previewFunnelAvailable: meta.previewFunnelAvailable === true,
      notes,
    },
    overview: {
      totalUsers: num(overview.totalUsers),
      newSignupsToday: num(overview.newSignupsToday),
      productDau: numOrNull(overview.productDau),
      productWau: numOrNull(overview.productWau),
      productMau: numOrNull(overview.productMau),
      dauMauRatio: numOrNull(overview.dauMauRatio),
    },
    growth: {
      signupsPerDay: parseSeries(growth.signupsPerDay),
      productActiveUsersPerDay: parseProductActiveSeries(growth.productActiveUsersPerDay),
    },
    retention: {
      d1Rate: numOrNull(retention.d1Rate),
      d7Rate: numOrNull(retention.d7Rate),
      d30Rate: numOrNull(retention.d30Rate),
      returningUsersPerDay: parseSeries(retention.returningUsersPerDay),
      cohortSampleSignups: num(retention.cohortSampleSignups),
      d1MatureCohortSize: num(retention.d1MatureCohortSize),
      d7MatureCohortSize: num(retention.d7MatureCohortSize),
      d30MatureCohortSize: num(retention.d30MatureCohortSize),
      insufficientData: retention.insufficientData === true,
    },
    trading: {
      tradesCreatedPerDay: parseSeries(trading.tradesCreatedPerDay),
      activeTradersPerDay: parseSeries(trading.activeTradersPerDay),
      tradesPerActiveTraderLatestDay: numOrNull(trading.tradesPerActiveTraderLatestDay),
      importTotalsInPeriod: parseImportTotals(imports),
    },
    social: {
      profileViewsPerDay: parseSeries(social.profileViewsPerDay),
      uniqueProfileViewersPerDay: parseSeries(social.uniqueProfileViewersPerDay),
      postsPerDay: parseSeries(social.postsPerDay),
      featureEngagementPerDay: parseSeries(social.featureEngagementPerDay),
    },
    features: {
      topFeatures: parseFeatureRows(features.topFeatures),
    },
    traxsProPreview: {
      available: preview.available === true,
      startsPerDay: parseSeries(preview.startsPerDay),
      exitsPerDay: parseSeries(preview.exitsPerDay),
      upgradeTapsPerDay: parseSeries(preview.upgradeTapsPerDay),
      funnelTotals: {
        starts: num(funnel.starts),
        exits: num(funnel.exits),
        upgradeTaps: num(funnel.upgradeTaps),
        startToUpgradeRate: numOrNull(funnel.startToUpgradeRate),
      },
    },
  }
}

export async function fetchAdminProductAnalyticsBundle(
  supabase: SupabaseClient,
  seriesDays = 30
): Promise<{ data: AdminProductAnalyticsBundle | null; error: Error | null }> {
  const days = Math.max(1, Math.min(90, Math.floor(Number(seriesDays)) || 30))
  const { data, error } = await supabase.rpc("admin_product_analytics_bundle", {
    p_series_days: days,
  })

  if (error) {
    return { data: null, error: new Error(error.message) }
  }

  let parsed: unknown = data
  if (typeof data === "string") {
    try {
      parsed = JSON.parse(data)
    } catch {
      return { data: null, error: new Error("Invalid product analytics response (JSON parse failed)") }
    }
  }

  const j = parsed as Record<string, unknown> | null
  if (!j || typeof j !== "object" || Array.isArray(j)) {
    return { data: null, error: new Error("Invalid product analytics response") }
  }

  return { data: mapRpcToBundle(j), error: null }
}

export function formatMetricUnavailable(value: number | null | undefined): string {
  if (value === null || value === undefined) return "—"
  return String(value)
}

export function formatPercent(value: number | null | undefined): string {
  if (value === null || value === undefined) return "—"
  return `${value.toFixed(1)}%`
}

export function retentionRateLabel(
  rate: number | null | undefined,
  matureCohortSize: number,
  insufficientData: boolean
): string {
  if (insufficientData || matureCohortSize <= 0) return "Insufficient data"
  return formatPercent(rate)
}

/** Chart-ready points: null / pre-tracking counts omitted so lines do not fake zero. */
export function productActiveChartData(points: ProductDailyCountPoint[]): { day: string; count: number }[] {
  return points
    .filter((p) => p.count != null)
    .map((p) => ({ day: p.day, count: p.count as number }))
}