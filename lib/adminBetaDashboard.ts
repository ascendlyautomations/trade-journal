import type { SupabaseClient } from "@supabase/supabase-js"

export type BetaActivityKind = "bug_report" | "feature_request" | "room_message" | "trade"

export type BetaDashboardActivityItem = {
  kind: BetaActivityKind
  id: string
  userId: string
  username: string
  summary: string
  createdAt: string
}

export type AdminBetaDashboardBundle = {
  totalBetaTesters: number
  activeBetaTesters7d: number
  tradesTotal: number
  trades7d: number
  postsTotal: number
  posts7d: number
  betaRoomMembers: number
  betaRoomMessages: number
  bugReportsTotal: number
  bugReportsOpen: number
  bugReportsResolved: number
  featureRequestsTotal: number
  featureRequestsOpen: number
  featureRequestsPlanned: number
  featureRequestsCompleted: number
  recentActivity: BetaDashboardActivityItem[]
}

export const BETA_ACTIVITY_PAGE_SIZE = 20

export function activityRowKey(row: Pick<BetaDashboardActivityItem, "kind" | "id">): string {
  return `${row.kind}-${row.id}`
}

/** Preserve order; drop duplicate kind+id rows (first wins). */
export function dedupeActivityRows(rows: BetaDashboardActivityItem[]): BetaDashboardActivityItem[] {
  const seen = new Set<string>()
  const out: BetaDashboardActivityItem[] = []
  for (const row of rows) {
    const key = activityRowKey(row)
    if (seen.has(key)) continue
    seen.add(key)
    out.push(row)
  }
  return out
}

export function mergeActivityRows(
  existing: BetaDashboardActivityItem[],
  incoming: BetaDashboardActivityItem[],
  append: boolean
): BetaDashboardActivityItem[] {
  if (!append) return dedupeActivityRows(incoming)
  return dedupeActivityRows([...existing, ...incoming])
}

export type FetchAdminBetaActivityParams = {
  limit?: number
  offset?: number
  search?: string | null
}

function num(v: unknown): number {
  if (typeof v === "number" && Number.isFinite(v)) return v
  if (typeof v === "string" && v.trim() !== "") {
    const n = Number(v)
    if (Number.isFinite(n)) return n
  }
  return 0
}

function parseActivity(raw: unknown): BetaDashboardActivityItem[] {
  if (!Array.isArray(raw)) return []
  const kinds = new Set<BetaActivityKind>([
    "bug_report",
    "feature_request",
    "room_message",
    "trade",
  ])
  return raw
    .map((row) => {
      const o = row as Record<string, unknown>
      const kind = String(o.kind ?? "").trim() as BetaActivityKind
      if (!kinds.has(kind)) return null
      return {
        kind,
        id: String(o.id ?? ""),
        userId: String(o.userId ?? ""),
        username: String(o.username ?? "").trim(),
        summary: String(o.summary ?? "").trim() || "—",
        createdAt: String(o.createdAt ?? ""),
      }
    })
    .filter((row): row is BetaDashboardActivityItem => row != null && row.id !== "")
}

function mapRpcToBundle(j: Record<string, unknown>): AdminBetaDashboardBundle {
  return {
    totalBetaTesters: num(j.totalBetaTesters),
    activeBetaTesters7d: num(j.activeBetaTesters7d),
    tradesTotal: num(j.tradesTotal),
    trades7d: num(j.trades7d),
    postsTotal: num(j.postsTotal),
    posts7d: num(j.posts7d),
    betaRoomMembers: num(j.betaRoomMembers),
    betaRoomMessages: num(j.betaRoomMessages),
    bugReportsTotal: num(j.bugReportsTotal),
    bugReportsOpen: num(j.bugReportsOpen),
    bugReportsResolved: num(j.bugReportsResolved),
    featureRequestsTotal: num(j.featureRequestsTotal),
    featureRequestsOpen: num(j.featureRequestsOpen),
    featureRequestsPlanned: num(j.featureRequestsPlanned),
    featureRequestsCompleted: num(j.featureRequestsCompleted),
    recentActivity: parseActivity(j.recentActivity),
  }
}

export async function fetchAdminBetaDashboardBundle(
  supabase: SupabaseClient
): Promise<{ data: AdminBetaDashboardBundle | null; error: Error | null }> {
  const { data, error } = await supabase.rpc("admin_beta_dashboard_bundle")

  if (error) {
    return { data: null, error: new Error(error.message) }
  }

  let parsed: unknown = data
  if (typeof data === "string") {
    try {
      parsed = JSON.parse(data)
    } catch {
      return { data: null, error: new Error("Invalid beta dashboard response (JSON parse failed)") }
    }
  }

  const j = parsed as Record<string, unknown> | null
  if (!j || typeof j !== "object" || Array.isArray(j)) {
    return { data: null, error: new Error("Invalid beta dashboard response") }
  }

  return { data: mapRpcToBundle(j), error: null }
}

export async function fetchAdminBetaActivity(
  supabase: SupabaseClient,
  params: FetchAdminBetaActivityParams = {}
): Promise<{ data: BetaDashboardActivityItem[]; error: Error | null }> {
  const limit = Math.max(1, Math.min(100, Math.floor(params.limit ?? BETA_ACTIVITY_PAGE_SIZE)))
  const offset = Math.max(0, Math.floor(params.offset ?? 0))
  const search = params.search?.trim() || null

  const { data, error } = await supabase.rpc("admin_beta_activity", {
    p_limit: limit,
    p_offset: offset,
    p_search: search,
  })

  if (error) {
    return { data: [], error: new Error(error.message) }
  }

  let parsed: unknown = data
  if (typeof data === "string") {
    try {
      parsed = JSON.parse(data)
    } catch {
      return { data: [], error: new Error("Invalid beta activity response (JSON parse failed)") }
    }
  }

  return { data: dedupeActivityRows(parseActivity(parsed)), error: null }
}

export function betaActivityKindLabel(kind: BetaActivityKind): string {
  switch (kind) {
    case "bug_report":
      return "Bug report"
    case "feature_request":
      return "Feature request"
    case "room_message":
      return "Beta room message"
    case "trade":
      return "Trade logged"
    default:
      return kind
  }
}
