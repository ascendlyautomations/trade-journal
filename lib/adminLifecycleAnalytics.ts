import type { SupabaseClient } from "@supabase/supabase-js"
import { retentionRateLabel, formatPercent } from "@/lib/adminProductAnalytics"
import type { AdminLifecycleAnalyticsQuery } from "@/lib/adminLifecycleAnalyticsFilters"
import { validateLifecycleAnalyticsQuery } from "@/lib/adminLifecycleAnalyticsFilters"

export type FunnelStage = {
  id: string
  label: string
  count: number
  conversionFromSignupPct?: number | null
  dropOffFromPriorPct?: number | null
  awaitingData?: boolean
}

export type AdminLifecycleAnalyticsBundle = {
  seriesDays: number
  meta: {
    periodStart: string | null
    periodEnd: string | null
    rangeMode: string
    productTrackingStartDate: string | null
    sessionMetricsAvailable: boolean
    productEventsAvailable: boolean
    notes: string[]
  }
  userGrowthActivation: {
    cohortSignups: number
    insufficientData: boolean
    stages: FunnelStage[]
    medianHoursToStage: {
      onboarding: number | null
      firstAccount: number | null
      firstTrade: number | null
      firstSocial: number | null
      firstReturnVisit: number | null
    }
  }
  traxsProConversion: {
    stages: FunnelStage[]
    platform: {
      paywallViews: { web: number; ios: number }
      upgradeClicks: { web: number; ios: number }
      previewStarts: { total: number }
    }
    previewStartsByFeature: {
      dashboard: number
      reports: number
      expenseTracker: number
    }
    billingInPeriod: {
      trials: number
      newSubscriptions: number
      cancellations: number
      appleExpired: number
    }
  }
  retentionChurn: {
    sessionRetention: {
      d1Rate: number | null
      d7Rate: number | null
      d30Rate: number | null
      cohortSampleSignups: number
      d1MatureCohortSize: number
      d7MatureCohortSize: number
      d30MatureCohortSize: number
      insufficientData: boolean
      definition: string
    }
    weeklyReturningUsers: { day: string; count: number }[]
    newVsReturningUsersPerDay: { day: string; newUsers: number; returningUsers: number }[]
    inactiveUsers: {
      inactive7Days: number
      inactive14Days: number
      inactive30Days: number
      asOfDate: string
    }
    subscriberChurn: {
      activeSubscribersAtPeriodStart: number | null
      activeSubscribersAtPeriodEnd: number
      grossChurnRatePct: number | null
      insufficientData: boolean
      definition: string
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

function parseStages(raw: unknown): FunnelStage[] {
  if (!Array.isArray(raw)) return []
  return raw.map((row) => {
    const o = row as Record<string, unknown>
    return {
      id: String(o.id ?? ""),
      label: String(o.label ?? ""),
      count: num(o.count),
      conversionFromSignupPct: numOrNull(o.conversionFromSignupPct),
      dropOffFromPriorPct: numOrNull(o.dropOffFromPriorPct),
      awaitingData: o.awaitingData === true,
    }
  })
}

function mapRpcToBundle(j: Record<string, unknown>): AdminLifecycleAnalyticsBundle {
  const meta = (j.meta as Record<string, unknown>) ?? {}
  const activation = (j.userGrowthActivation as Record<string, unknown>) ?? {}
  const traxs = (j.traxsProConversion as Record<string, unknown>) ?? {}
  const retention = (j.retentionChurn as Record<string, unknown>) ?? {}
  const session = (retention.sessionRetention as Record<string, unknown>) ?? {}
  const platform = (traxs.platform as Record<string, unknown>) ?? {}
  const previewBy = (traxs.previewStartsByFeature as Record<string, unknown>) ?? {}
  const billing = (traxs.billingInPeriod as Record<string, unknown>) ?? {}
  const inactive = (retention.inactiveUsers as Record<string, unknown>) ?? {}
  const subChurn = (retention.subscriberChurn as Record<string, unknown>) ?? {}
  const medians = (activation.medianHoursToStage as Record<string, unknown>) ?? {}
  const paywallViews = (platform.paywallViews as Record<string, unknown>) ?? {}
  const upgradeClicks = (platform.upgradeClicks as Record<string, unknown>) ?? {}
  const previewStarts = (platform.previewStarts as Record<string, unknown>) ?? {}

  return {
    seriesDays: num(j.seriesDays),
    meta: {
      periodStart: meta.periodStart != null ? String(meta.periodStart) : null,
      periodEnd: meta.periodEnd != null ? String(meta.periodEnd) : null,
      rangeMode: String(meta.rangeMode ?? "preset"),
      productTrackingStartDate:
        meta.productTrackingStartDate != null ? String(meta.productTrackingStartDate) : null,
      sessionMetricsAvailable: meta.sessionMetricsAvailable === true,
      productEventsAvailable: meta.productEventsAvailable === true,
      notes: Array.isArray(meta.notes) ? meta.notes.map(String) : [],
    },
    userGrowthActivation: {
      cohortSignups: num(activation.cohortSignups),
      insufficientData: activation.insufficientData === true,
      stages: parseStages(activation.stages),
      medianHoursToStage: {
        onboarding: numOrNull(medians.onboarding),
        firstAccount: numOrNull(medians.firstAccount),
        firstTrade: numOrNull(medians.firstTrade),
        firstSocial: numOrNull(medians.firstSocial),
        firstReturnVisit: numOrNull(medians.firstReturnVisit),
      },
    },
    traxsProConversion: {
      stages: parseStages(traxs.stages),
      platform: {
        paywallViews: { web: num(paywallViews.web), ios: num(paywallViews.ios) },
        upgradeClicks: { web: num(upgradeClicks.web), ios: num(upgradeClicks.ios) },
        previewStarts: { total: num(previewStarts.total) },
      },
      previewStartsByFeature: {
        dashboard: num(previewBy.dashboard),
        reports: num(previewBy.reports),
        expenseTracker: num(previewBy.expenseTracker),
      },
      billingInPeriod: {
        trials: num(billing.trials),
        newSubscriptions: num(billing.newSubscriptions),
        cancellations: num(billing.cancellations),
        appleExpired: num(billing.appleExpired),
      },
    },
    retentionChurn: {
      sessionRetention: {
        d1Rate: numOrNull(session.d1Rate),
        d7Rate: numOrNull(session.d7Rate),
        d30Rate: numOrNull(session.d30Rate),
        cohortSampleSignups: num(session.cohortSampleSignups),
        d1MatureCohortSize: num(session.d1MatureCohortSize),
        d7MatureCohortSize: num(session.d7MatureCohortSize),
        d30MatureCohortSize: num(session.d30MatureCohortSize),
        insufficientData: session.insufficientData === true,
        definition: String(session.definition ?? ""),
      },
      weeklyReturningUsers: Array.isArray(retention.weeklyReturningUsers)
        ? retention.weeklyReturningUsers.map((row) => {
            const o = row as Record<string, unknown>
            return { day: String(o.day ?? ""), count: num(o.count) }
          })
        : [],
      newVsReturningUsersPerDay: Array.isArray(retention.newVsReturningUsersPerDay)
        ? retention.newVsReturningUsersPerDay.map((row) => {
            const o = row as Record<string, unknown>
            return {
              day: String(o.day ?? ""),
              newUsers: num(o.newUsers),
              returningUsers: num(o.returningUsers),
            }
          })
        : [],
      inactiveUsers: {
        inactive7Days: num(inactive.inactive7Days),
        inactive14Days: num(inactive.inactive14Days),
        inactive30Days: num(inactive.inactive30Days),
        asOfDate: String(inactive.asOfDate ?? ""),
      },
      subscriberChurn: {
        activeSubscribersAtPeriodStart: numOrNull(subChurn.activeSubscribersAtPeriodStart),
        activeSubscribersAtPeriodEnd: num(subChurn.activeSubscribersAtPeriodEnd),
        grossChurnRatePct: numOrNull(subChurn.grossChurnRatePct),
        insufficientData: subChurn.insufficientData === true,
        definition: String(subChurn.definition ?? ""),
      },
    },
  }
}

export async function fetchAdminLifecycleAnalyticsBundle(
  supabase: SupabaseClient,
  query: AdminLifecycleAnalyticsQuery
): Promise<{ data: AdminLifecycleAnalyticsBundle | null; error: Error | null }> {
  const validation = validateLifecycleAnalyticsQuery(query)
  if (!validation.valid) {
    return { data: null, error: new Error(validation.message ?? "Invalid range") }
  }

  const rpcArgs: Record<string, unknown> = {}
  if (query.preset === "custom") {
    rpcArgs.p_series_days = null
    rpcArgs.p_start_date = query.customStartDate
    rpcArgs.p_end_date = query.customEndDate
  } else {
    rpcArgs.p_series_days = query.preset
    rpcArgs.p_start_date = null
    rpcArgs.p_end_date = null
  }

  const { data, error } = await supabase.rpc("admin_lifecycle_analytics_bundle", rpcArgs)
  if (error) return { data: null, error: new Error(error.message) }
  if (!data || typeof data !== "object") {
    return { data: null, error: new Error("Empty lifecycle analytics response") }
  }
  return { data: mapRpcToBundle(data as Record<string, unknown>), error: null }
}

export function funnelStageConversionLabel(stage: FunnelStage): string {
  if (stage.awaitingData) return "Awaiting data"
  if (stage.conversionFromSignupPct != null) return `${formatPercent(stage.conversionFromSignupPct)} from signup`
  return "—"
}

export { retentionRateLabel, formatPercent }