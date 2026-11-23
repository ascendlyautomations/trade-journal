export type HistoricalActivityFilter = "all" | "trading" | "social"

export type HistoricalRangePreset = 30 | 90 | 180 | 365 | "custom"

export type HistoricalEngagementQuery = {
  preset: HistoricalRangePreset
  customStartDate: string | null
  customEndDate: string | null
  activityFilter: HistoricalActivityFilter
}

export const HISTORICAL_ENGAGEMENT_STORAGE_KEY = "tradetraxs.admin.historicalEngagement.v1"

export const DEFAULT_HISTORICAL_ENGAGEMENT_QUERY: HistoricalEngagementQuery = {
  preset: 90,
  customStartDate: null,
  customEndDate: null,
  activityFilter: "all",
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

export type HistoricalDateValidation = {
  valid: boolean
  message: string | null
}

export function validateHistoricalEngagementQuery(
  query: HistoricalEngagementQuery,
  todayYmd: string = utcTodayYmd()
): HistoricalDateValidation {
  if (!["all", "trading", "social"].includes(query.activityFilter)) {
    return { valid: false, message: "Invalid activity filter." }
  }

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

export function loadHistoricalEngagementQuery(): HistoricalEngagementQuery {
  if (typeof window === "undefined") return DEFAULT_HISTORICAL_ENGAGEMENT_QUERY
  try {
    const raw = sessionStorage.getItem(HISTORICAL_ENGAGEMENT_STORAGE_KEY)
    if (!raw) return DEFAULT_HISTORICAL_ENGAGEMENT_QUERY
    const parsed = JSON.parse(raw) as Partial<HistoricalEngagementQuery>
    return {
      preset: parsed.preset ?? DEFAULT_HISTORICAL_ENGAGEMENT_QUERY.preset,
      customStartDate: parsed.customStartDate ?? null,
      customEndDate: parsed.customEndDate ?? null,
      activityFilter: parsed.activityFilter ?? DEFAULT_HISTORICAL_ENGAGEMENT_QUERY.activityFilter,
    }
  } catch {
    return DEFAULT_HISTORICAL_ENGAGEMENT_QUERY
  }
}

export function saveHistoricalEngagementQuery(query: HistoricalEngagementQuery): void {
  if (typeof window === "undefined") return
  sessionStorage.setItem(HISTORICAL_ENGAGEMENT_STORAGE_KEY, JSON.stringify(query))
}

export function historicalQueryLabel(query: HistoricalEngagementQuery): string {
  if (query.preset === "custom") {
    return `${query.customStartDate ?? "—"} → ${query.customEndDate ?? "—"}`
  }
  if (query.preset === 180) return "6M"
  if (query.preset === 365) return "1Y"
  return `${query.preset}D`
}