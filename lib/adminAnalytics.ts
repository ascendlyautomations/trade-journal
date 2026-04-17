import type { SupabaseClient } from "@supabase/supabase-js"

/**
 * DAU / WAU (see `DAU_DEFINITION`):
 * Distinct `user_id` across trades, feed posts, profile wall posts, stories,
 * feedback_submissions, and support_tickets with `created_at` in the window.
 */
export const DAU_DEFINITION =
  "Distinct users who created a trade, feed post, profile post, story, feedback ticket, or support ticket in the time window (UTC)."

/** One point from `series.usersPerDay` | `series.tradesPerDay` | `series.postsPerDay` (RPC). */
export type DailyCountPoint = { day: string; count: number }

/** Matches `public.admin_analytics_bundle` JSON (camelCase only). */
export type AdminAnalyticsBundle = {
  totalUsers: number
  newUsersToday: number
  newUsersWeek: number
  dailyActiveUsers: number
  weeklyActiveUsers: number
  totalTrades: number
  tradesToday: number
  tradesWeek: number
  totalPosts: number
  postsToday: number
  postsWeek: number
  bannedUsers: number
  totalFeedback: number
  openFeedback: number
  totalSupport: number
  openSupport: number
  seriesDays: number
  series: {
    usersPerDay: DailyCountPoint[]
    tradesPerDay: DailyCountPoint[]
    postsPerDay: DailyCountPoint[]
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

/** RPC points: `{ day, count }` only. */
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

function readSeriesObject(j: Record<string, unknown>): AdminAnalyticsBundle["series"] {
  const s = j.series
  if (!s || typeof s !== "object" || Array.isArray(s)) {
    return { usersPerDay: [], tradesPerDay: [], postsPerDay: [] }
  }
  const o = s as Record<string, unknown>
  return {
    usersPerDay: parseSeries(o.usersPerDay),
    tradesPerDay: parseSeries(o.tradesPerDay),
    postsPerDay: parseSeries(o.postsPerDay),
  }
}

/** Map RPC JSON → view model (camelCase keys only, per current `admin_analytics_bundle`). */
function mapRpcToBundle(j: Record<string, unknown>): AdminAnalyticsBundle {
  return {
    totalUsers: num(j.totalUsers),
    newUsersToday: num(j.newUsersToday),
    newUsersWeek: num(j.newUsersWeek),
    dailyActiveUsers: num(j.dailyActiveUsers),
    weeklyActiveUsers: num(j.weeklyActiveUsers),
    totalTrades: num(j.totalTrades),
    tradesToday: num(j.tradesToday),
    tradesWeek: num(j.tradesWeek),
    totalPosts: num(j.totalPosts),
    postsToday: num(j.postsToday),
    postsWeek: num(j.postsWeek),
    bannedUsers: num(j.bannedUsers),
    totalFeedback: num(j.totalFeedback),
    openFeedback: num(j.openFeedback),
    totalSupport: num(j.totalSupport),
    openSupport: num(j.openSupport),
    seriesDays: num(j.seriesDays),
    series: readSeriesObject(j),
  }
}

export async function fetchAdminAnalyticsBundle(
  supabase: SupabaseClient,
  seriesDays = 14
): Promise<{ data: AdminAnalyticsBundle | null; error: Error | null }> {
  const days = Math.max(1, Math.min(90, Math.floor(Number(seriesDays)) || 14))
  const { data, error } = await supabase.rpc("admin_analytics_bundle", { p_series_days: days })

  if (error) {
    return { data: null, error: new Error(error.message) }
  }

  let parsed: unknown = data
  if (typeof data === "string") {
    try {
      parsed = JSON.parse(data)
    } catch {
      return { data: null, error: new Error("Invalid analytics response (JSON parse failed)") }
    }
  }

  const j = parsed as Record<string, unknown> | null
  if (!j || typeof j !== "object" || Array.isArray(j)) {
    return { data: null, error: new Error("Invalid analytics response") }
  }

  if (process.env.NODE_ENV !== "production") {
    console.debug("[admin/analytics] raw admin_analytics_bundle", JSON.stringify(parsed, null, 2))
  }

  const bundle = mapRpcToBundle(j)

  if (process.env.NODE_ENV !== "production") {
    console.debug("[admin/analytics] parsed bundle", bundle)
    console.debug("[admin/analytics] series.usersPerDay", bundle.series.usersPerDay)
    console.debug("[admin/analytics] series.tradesPerDay", bundle.series.tradesPerDay)
    console.debug("[admin/analytics] series.postsPerDay", bundle.series.postsPerDay)
  }

  return { data: bundle, error: null }
}

export type AdminAuditFeedItem = {
  id: string
  admin_user_id: string
  admin_email: string | null
  target_user_id: string | null
  target_email: string | null
  action: string
  target_type: string | null
  target_id: string | null
  details: Record<string, unknown> | null
  created_at: string
}

export async function fetchAdminRecentAudit(
  supabase: SupabaseClient,
  limit = 12
): Promise<{ data: AdminAuditFeedItem[]; error: Error | null }> {
  const { data, error } = await supabase.rpc("admin_recent_audit", { p_limit: limit })

  if (error) {
    return { data: [], error: new Error(error.message) }
  }

  let parsed: unknown = data
  if (data == null) {
    return { data: [], error: null }
  }
  if (typeof data === "string") {
    try {
      parsed = JSON.parse(data)
    } catch {
      parsed = []
    }
  }

  if (!Array.isArray(parsed)) {
    return { data: [], error: null }
  }

  const rows = parsed.map((raw) => {
    const o = raw as Record<string, unknown>
    return {
      id: String(o.id ?? ""),
      admin_user_id: String(o.admin_user_id ?? ""),
      admin_email: o.admin_email != null ? String(o.admin_email) : null,
      target_user_id: o.target_user_id != null ? String(o.target_user_id) : null,
      target_email: o.target_email != null ? String(o.target_email) : null,
      action: String(o.action ?? ""),
      target_type: o.target_type != null ? String(o.target_type) : null,
      target_id: o.target_id != null ? String(o.target_id) : null,
      details: (o.details as Record<string, unknown> | null) ?? null,
      created_at: String(o.created_at ?? ""),
    }
  })

  return { data: rows, error: null }
}
