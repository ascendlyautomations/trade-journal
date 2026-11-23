export type LifecycleRangePreset = 30 | 90 | 180 | 365 | "custom"

export type AdminLifecycleAnalyticsQuery = {
  preset: LifecycleRangePreset
  customStartDate: string | null
  customEndDate: string | null
}

export const LIFECYCLE_ANALYTICS_STORAGE_KEY = "tradetraxs.admin.lifecycleAnalytics.v1"

export const DEFAULT_LIFECYCLE_ANALYTICS_QUERY: AdminLifecycleAnalyticsQuery = {
  preset: 90,
  customStartDate: null,
  customEndDate: null,
}

const PRESETS = new Set([30, 90, 180, 365])

export function utcTodayYmd(): string {
  return new Date().toISOString().slice(0, 10)
}

export function parseIsoDateYmd(value: string): Date | null {
  const trimmed = value.trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return null
  const d = new Date(`${trimmed}T00:00:00Z`)
  return Number.isNaN(d.getTime()) ? null : d
}

export type LifecycleDateValidation = {
  valid: boolean
  message: string | null
}

export function validateLifecycleAnalyticsQuery(
  query: AdminLifecycleAnalyticsQuery,
  todayYmd: string = utcTodayYmd()
): LifecycleDateValidation {
  if (query.preset !== "custom") {
    if (!PRESETS.has(query.preset)) {
      return { valid: false, message: "Invalid preset range." }
    }
    return { valid: true, message: null }
  }

  const start = query.customStartDate ? parseIsoDateYmd(query.customStartDate) : null
  const end = query.customEndDate ? parseIsoDateYmd(query.customEndDate) : null
  if (!start || !end) {
    return { valid: false, message: "Choose a start and end date." }
  }
  const today = parseIsoDateYmd(todayYmd)
  if (!today) return { valid: false, message: "Invalid today." }

  if (start > today || end > today) {
    return { valid: false, message: "Dates cannot be in the future (UTC)." }
  }
  if (start > end) {
    return { valid: false, message: "Start must be on or before end." }
  }
  const spanDays = Math.floor((end.getTime() - start.getTime()) / 86_400_000) + 1
  if (spanDays > 365) {
    return { valid: false, message: "Custom range cannot exceed 365 days." }
  }
  return { valid: true, message: null }
}

export function loadLifecycleAnalyticsQuery(): AdminLifecycleAnalyticsQuery {
  if (typeof window === "undefined") return DEFAULT_LIFECYCLE_ANALYTICS_QUERY
  try {
    const raw = sessionStorage.getItem(LIFECYCLE_ANALYTICS_STORAGE_KEY)
    if (!raw) return DEFAULT_LIFECYCLE_ANALYTICS_QUERY
    const parsed = JSON.parse(raw) as Partial<AdminLifecycleAnalyticsQuery>
    return {
      preset: parsed.preset ?? DEFAULT_LIFECYCLE_ANALYTICS_QUERY.preset,
      customStartDate: parsed.customStartDate ?? null,
      customEndDate: parsed.customEndDate ?? null,
    }
  } catch {
    return DEFAULT_LIFECYCLE_ANALYTICS_QUERY
  }
}

export function saveLifecycleAnalyticsQuery(query: AdminLifecycleAnalyticsQuery): void {
  if (typeof window === "undefined") return
  sessionStorage.setItem(LIFECYCLE_ANALYTICS_STORAGE_KEY, JSON.stringify(query))
}