import { supabase } from "./supabaseClient"
import type { LeaderboardAccountTypeFilter, LeaderboardView } from "./leaderboardChart.ts"

export const LEADERBOARD_BOOTSTRAP_PAGE_SIZE = 100

export type LeaderboardBootstrapTimeframe =
  | "today"
  | "week"
  | "month"
  | "year"
  | "all_time"

export type LeaderboardBootstrapCategory =
  | "pnl"
  | "win_rate"
  | "profit_factor"
  | "expectancy"
  | "rr"
  | "winstreak"
  | "profitpercent"
  | "consistency"
  | "followers"

export type LeaderboardBootstrapAudience = "all" | "friends" | "following"

export type LeaderboardBootstrapRow = {
  profileId: string
  username: string | null
  displayName: string | null
  avatarUrl: string | null
  followerCount: number
  totalPnl: number
  tradeCount: number
  avgRr: number | null
  winRate: number | null
  profitFactor: number | null
  expectancy: number | null
  winStreak: number
  profitPercent: number | null
  consistency: number | null
  sortKey: number
}

export type LeaderboardBootstrapResult = {
  timeframe: string
  category: string
  rows: LeaderboardBootstrapRow[]
  nextCursor: string | null
}

export type LeaderboardPageTimeframe =
  | { kind: "rpc"; value: LeaderboardBootstrapTimeframe }
  | { kind: "legacy"; value: LeaderboardView }

export const LEADERBOARD_BOOTSTRAP_TIMEFRAME_OPTIONS: {
  label: string
  timeframe: LeaderboardPageTimeframe
}[] = [
  { label: "Today", timeframe: { kind: "rpc", value: "today" } },
  { label: "Week", timeframe: { kind: "rpc", value: "week" } },
  { label: "Month", timeframe: { kind: "rpc", value: "month" } },
  { label: "Year", timeframe: { kind: "rpc", value: "year" } },
  { label: "All Time", timeframe: { kind: "rpc", value: "all_time" } },
  { label: "90D", timeframe: { kind: "legacy", value: "90D" } },
  { label: "Custom", timeframe: { kind: "legacy", value: "Custom" } },
]

export const LEADERBOARD_CATEGORY_OPTIONS: {
  label: string
  value: LeaderboardBootstrapCategory
}[] = [
  { label: "PnL", value: "pnl" },
  { label: "Win Rate", value: "win_rate" },
  { label: "Profit Factor", value: "profit_factor" },
  { label: "Expectancy", value: "expectancy" },
  { label: "RR", value: "rr" },
  { label: "Win Streak", value: "winstreak" },
  { label: "Profit %", value: "profitpercent" },
  { label: "Followers", value: "followers" },
  { label: "Consistency", value: "consistency" },
]

export const LEADERBOARD_AUDIENCE_OPTIONS: {
  label: string
  value: LeaderboardBootstrapAudience
}[] = [
  { label: "All", value: "all" },
  { label: "Friends", value: "friends" },
  { label: "Following", value: "following" },
]

export function leaderboardTimeframeSelectValue(
  timeframe: LeaderboardPageTimeframe
): string {
  return timeframe.kind === "rpc"
    ? `rpc:${timeframe.value}`
    : `legacy:${timeframe.value}`
}

export function parseLeaderboardTimeframeSelectValue(
  raw: string
): LeaderboardPageTimeframe {
  if (raw.startsWith("rpc:")) {
    const value = raw.slice(4) as LeaderboardBootstrapTimeframe
    return { kind: "rpc", value }
  }
  if (raw.startsWith("legacy:")) {
    const value = raw.slice(7) as LeaderboardView
    return { kind: "legacy", value }
  }
  return { kind: "rpc", value: "month" }
}

export function usesLeaderboardBootstrapRankings(
  timeframe: LeaderboardPageTimeframe,
  accountType: LeaderboardAccountTypeFilter
): boolean {
  return timeframe.kind === "rpc" && accountType === "all"
}

export function leaderboardChartEligible(
  category: LeaderboardBootstrapCategory,
  audience: LeaderboardBootstrapAudience,
  accountType: LeaderboardAccountTypeFilter,
  timeframe: LeaderboardPageTimeframe
): boolean {
  return (
    category === "pnl" &&
    audience === "all" &&
    accountType === "all" &&
    timeframe.kind === "rpc"
  )
}

/** Maps RPC windows to legacy ranked-window views for the P&L chart sidecar. */
export function newYorkTodayYmd(now: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/New_York",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now)
}

export function legacyViewForRpcChartTimeframe(
  timeframe: LeaderboardBootstrapTimeframe
): LeaderboardView {
  switch (timeframe) {
    case "today":
      return "Custom"
    case "week":
      return "7D"
    case "month":
      return "30D"
    case "year":
      return "YTD"
    case "all_time":
      return "ALL"
  }
}

function num(value: unknown): number {
  const n = Number(value)
  return Number.isFinite(n) ? n : 0
}

function nullableNum(value: unknown): number | null {
  if (value === null || value === undefined) return null
  const n = Number(value)
  return Number.isFinite(n) ? n : null
}

function parseBootstrapRow(raw: Record<string, unknown>): LeaderboardBootstrapRow | null {
  const profileId = String(raw.profile_id ?? "").trim()
  if (!profileId) return null
  return {
    profileId,
    username: raw.username != null ? String(raw.username) : null,
    displayName: raw.display_name != null ? String(raw.display_name) : null,
    avatarUrl: raw.avatar_url != null ? String(raw.avatar_url) : null,
    followerCount: num(raw.follower_count),
    totalPnl: num(raw.total_pnl),
    tradeCount: num(raw.trade_count),
    avgRr: nullableNum(raw.avg_rr),
    winRate: nullableNum(raw.win_rate),
    profitFactor: nullableNum(raw.profit_factor),
    expectancy: nullableNum(raw.expectancy),
    winStreak: num(raw.win_streak),
    profitPercent: nullableNum(raw.profit_percent),
    consistency: nullableNum(raw.consistency),
    sortKey: num(raw.sort_key),
  }
}

export function normalizeLeaderboardBootstrapPayload(
  raw: unknown
): LeaderboardBootstrapResult | null {
  if (!raw || typeof raw !== "object") return null
  const root = raw as Record<string, unknown>
  const data = root.data
  if (!data || typeof data !== "object") return null
  const block = data as Record<string, unknown>
  const rowsRaw = Array.isArray(block.rows) ? block.rows : []
  const rows: LeaderboardBootstrapRow[] = []
  for (const item of rowsRaw) {
    if (!item || typeof item !== "object") continue
    const parsed = parseBootstrapRow(item as Record<string, unknown>)
    if (parsed) rows.push(parsed)
  }
  const nextCursor =
    block.next_cursor === null || block.next_cursor === undefined
      ? null
      : String(block.next_cursor)
  return {
    timeframe: String(block.timeframe ?? ""),
    category: String(block.category ?? ""),
    rows,
    nextCursor: nextCursor && nextCursor.length > 0 ? nextCursor : null,
  }
}

export async function fetchLeaderboardBootstrapPage(args: {
  timeframe: LeaderboardBootstrapTimeframe
  category: LeaderboardBootstrapCategory
  audience: LeaderboardBootstrapAudience
  cursor?: string | null
  limit?: number
}): Promise<LeaderboardBootstrapResult> {
  const { data, error } = await supabase.rpc("rpc_v1_leaderboard_bootstrap", {
    p_timeframe: args.timeframe,
    p_category: args.category,
    p_audience: args.audience,
    p_limit: args.limit ?? LEADERBOARD_BOOTSTRAP_PAGE_SIZE,
    p_cursor: args.cursor ?? undefined,
  })

  if (error) {
    console.error("[leaderboard] bootstrap rpc error:", error)
    throw new Error("Couldn't load leaderboard rankings. Please try again.")
  }

  const parsed = normalizeLeaderboardBootstrapPayload(data)
  if (!parsed) {
    throw new Error("Couldn't load leaderboard rankings. Please try again.")
  }
  return parsed
}

export function bootstrapRowsToProfiles(
  rows: LeaderboardBootstrapRow[]
): Record<
  string,
  {
    id: string
    username: string | null
    name: string | null
    avatar_url: string | null
  }
> {
  const map: Record<
    string,
    {
      id: string
      username: string | null
      name: string | null
      avatar_url: string | null
    }
  > = {}
  for (const row of rows) {
    map[row.profileId] = {
      id: row.profileId,
      username: row.username,
      name: row.displayName,
      avatar_url: row.avatarUrl,
    }
  }
  return map
}
