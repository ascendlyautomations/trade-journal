/**
 * Leaderboard chart pipeline: performance windows, daily chart buckets (NY calendar).
 * Used by app/leaderboard/page.tsx — keep logic here, not scattered in JSX.
 */

export type LeaderboardView = "7D" | "30D" | "90D" | "YTD" | "ALL"

export type TradeForLeaderboard = {
  user_id: string
  pnl?: number | string | null
  rr?: number | string | null
  created_at: string
}

export type LeaderboardChartRow = {
  /** Stable id for the bucket (not necessarily the axis label) */
  bucketId: string
  /** X-axis label */
  label: string
  sortKey: number
  average: number
  best: number
  worst: number
  you: number
}

export type LeaderboardTodayStats = {
  yourTradeCount: number
  yourAvgPnl: number
  /** null when no trade in the window has a valid RR value */
  yourAvgRR: number | null
  globalAvgPnl: number
  /** null when no trade in the window has a valid RR value */
  globalAvgRR: number | null
  globalTradeCount: number
  percentileTopPct: string
}

const NY = "America/New_York"
const DAY_MS = 24 * 60 * 60 * 1000

function num(v: number | string | null | undefined): number {
  const n = Number(v)
  return Number.isFinite(n) ? n : 0
}

/** Valid numeric RR only; null/undefined/empty/NaN excluded from averages. */
function rrValue(raw: unknown): number | null {
  if (raw === null || raw === undefined) return null
  if (typeof raw === "string" && raw.trim() === "") return null
  const n = Number(raw)
  return Number.isFinite(n) ? n : null
}

/** Mean RR over trades that have a valid RR (0 is valid). Null if none. */
function averageValidRR(trades: TradeForLeaderboard[]): number | null {
  let sum = 0
  let n = 0
  for (const t of trades) {
    const v = rrValue(t.rr)
    if (v === null) continue
    sum += v
    n += 1
  }
  return n > 0 ? sum / n : null
}

/** Calendar date in America/New_York for this instant: YYYY-MM-DD */
function formatDateNY(iso: string): string {
  const d = new Date(iso)
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: NY,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d)
}

function parseYmd(ymd: string): { y: number; m: number; day: number } {
  const [y, m, day] = ymd.split("-").map((x) => Number(x))
  return { y, m, day }
}

/** Gregorian civil date math at UTC noon (stable weekday / DST). */
function addDaysYmd(ymd: string, delta: number): string {
  const { y, m, day } = parseYmd(ymd)
  const t = Date.UTC(y, m - 1, day + delta, 12, 0, 0)
  const d = new Date(t)
  const yy = d.getUTCFullYear()
  const mm = d.getUTCMonth() + 1
  const dd = d.getUTCDate()
  return `${yy}-${String(mm).padStart(2, "0")}-${String(dd).padStart(2, "0")}`
}

function ymdCompare(a: string, b: string): number {
  return a.localeCompare(b)
}

function getDailyBucketId(createdAtIso: string): {
  bucketId: string
  sortKey: number
} {
  const ymdNY = formatDateNY(createdAtIso)
  const { y, m, day } = parseYmd(ymdNY)
  return { bucketId: ymdNY, sortKey: y * 10000 + m * 100 + day }
}

function labelForDailyBucket(bucketId: string): string {
  const { y, m, day } = parseYmd(bucketId)
  return `${m}/${day}/${y}`
}

/** All daily bucket ids from min trade day through end (NY), inclusive. */
function enumerateDailyBucketIds(
  minYmdNY: string,
  endYmdNY: string
): { bucketId: string; sortKey: number }[] {
  const out: { bucketId: string; sortKey: number }[] = []
  let cur = minYmdNY
  while (ymdCompare(cur, endYmdNY) <= 0) {
    const { y, m, day } = parseYmd(cur)
    const sortKey = y * 10000 + m * 100 + day
    out.push({ bucketId: cur, sortKey })
    cur = addDaysYmd(cur, 1)
  }
  return out
}

function emptyWindowStats(): LeaderboardTodayStats {
  return {
    yourTradeCount: 0,
    yourAvgPnl: 0,
    yourAvgRR: null,
    globalAvgPnl: 0,
    globalAvgRR: null,
    globalTradeCount: 0,
    percentileTopPct: "0.0",
  }
}

/** Client-side performance window filter (runs on Phase 1 paginated dataset). */
export function filterTradesForLeaderboardWindow(
  trades: TradeForLeaderboard[],
  view: LeaderboardView,
  now: Date = new Date()
): TradeForLeaderboard[] {
  const valid = trades.filter((t) => t?.created_at && t.user_id)

  if (view === "ALL") return valid

  if (view === "YTD") {
    const todayYmd = formatDateNY(now.toISOString())
    const ytdStart = `${parseYmd(todayYmd).y}-01-01`
    return valid.filter(
      (t) => ymdCompare(formatDateNY(t.created_at), ytdStart) >= 0
    )
  }

  const days = view === "7D" ? 7 : view === "30D" ? 30 : 90
  const cutoffMs = now.getTime() - days * DAY_MS
  return valid.filter((t) => new Date(t.created_at).getTime() >= cutoffMs)
}

function getChartWindowStartYmd(
  view: LeaderboardView,
  now: Date
): string | null {
  if (view === "ALL") return null

  const todayYmd = formatDateNY(now.toISOString())

  if (view === "YTD") {
    return `${parseYmd(todayYmd).y}-01-01`
  }

  const days = view === "7D" ? 7 : view === "30D" ? 30 : 90
  return formatDateNY(new Date(now.getTime() - days * DAY_MS).toISOString())
}

type UserAgg = { pnl: number; rr: number; count: number }

function emptyUserMap(): Record<string, UserAgg> {
  return {}
}

/**
 * Build chart rows + sidebar stats from raw trades.
 * - Trades filtered by selected performance window before aggregation.
 * - Chart uses daily NY buckets within the window.
 * - Sidebar stats cover the full selected window (not a single calendar bucket).
 */
export function buildLeaderboardChartData(
  trades: TradeForLeaderboard[],
  view: LeaderboardView,
  userId: string | null
): {
  chartData: LeaderboardChartRow[]
  todayStats: LeaderboardTodayStats
  hasData: boolean
} {
  const now = new Date()
  const todayYmd = formatDateNY(now.toISOString())
  const windowTrades = filterTradesForLeaderboardWindow(trades, view, now)

  if (windowTrades.length === 0) {
    return {
      chartData: [],
      todayStats: {
        ...emptyWindowStats(),
        percentileTopPct: userId ? "0.0" : "—",
      },
      hasData: false,
    }
  }

  const byBucket: Record<string, Record<string, UserAgg>> = {}

  for (const t of windowTrades) {
    const { bucketId } = getDailyBucketId(t.created_at)
    if (!byBucket[bucketId]) byBucket[bucketId] = emptyUserMap()
    const m = byBucket[bucketId]
    if (!m[t.user_id]) {
      m[t.user_id] = { pnl: 0, rr: 0, count: 0 }
    }
    m[t.user_id].pnl += num(t.pnl)
    m[t.user_id].rr += num(t.rr)
    m[t.user_id].count += 1
  }

  let minTradeYmd = todayYmd
  for (const t of windowTrades) {
    const ymd = formatDateNY(t.created_at)
    if (ymdCompare(ymd, minTradeYmd) < 0) minTradeYmd = ymd
  }

  const windowStartYmd = getChartWindowStartYmd(view, now)
  const chartStartYmd =
    windowStartYmd && ymdCompare(windowStartYmd, minTradeYmd) > 0
      ? windowStartYmd
      : minTradeYmd

  const bucketSequence = enumerateDailyBucketIds(chartStartYmd, todayYmd)

  const chartData: LeaderboardChartRow[] = bucketSequence.map(
    ({ bucketId, sortKey }) => {
      const userMap = byBucket[bucketId] || emptyUserMap()
      const entries = Object.entries(userMap).filter(([, agg]) => agg.count > 0)
      const pnls = entries.map(([, agg]) => agg.pnl)

      const average =
        pnls.length > 0 ? pnls.reduce((a, b) => a + b, 0) / pnls.length : 0
      const best = pnls.length > 0 ? Math.max(...pnls) : 0
      const worst = pnls.length > 0 ? Math.min(...pnls) : 0

      const youAgg = userId ? userMap[userId] : undefined
      const you = youAgg && youAgg.count > 0 ? youAgg.pnl : 0

      return {
        bucketId,
        label: labelForDailyBucket(bucketId),
        sortKey,
        average,
        best,
        worst,
        you,
      }
    }
  )

  const yourTrades = userId
    ? windowTrades.filter((t) => t.user_id === userId)
    : []

  const yourTradeCount = yourTrades.length
  const yourAvgPnl =
    yourTradeCount > 0
      ? yourTrades.reduce((s, t) => s + num(t.pnl), 0) / yourTradeCount
      : 0
  const yourAvgRR = averageValidRR(yourTrades)

  const globalTradeCount = windowTrades.length
  const globalAvgPnl =
    globalTradeCount > 0
      ? windowTrades.reduce((s, t) => s + num(t.pnl), 0) / globalTradeCount
      : 0
  const globalAvgRR = averageValidRR(windowTrades)

  const userTotals: Record<string, number> = {}
  for (const t of windowTrades) {
    userTotals[t.user_id] = (userTotals[t.user_id] || 0) + num(t.pnl)
  }

  const yourTotal = userId ? userTotals[userId] || 0 : 0

  /**
   * "Top X%": fraction of *other* traders whose window P&L sum is strictly
   * below yours. Self excluded from the pool.
   */
  let percentileTopPct = "0.0"
  if (!userId) {
    percentileTopPct = "—"
  } else {
    const peerPnls = Object.entries(userTotals)
      .filter(([uid]) => uid !== userId)
      .map(([, pnl]) => pnl)

    if (peerPnls.length === 0) {
      percentileTopPct = yourTradeCount > 0 ? "100.0" : "0.0"
    } else {
      const beaten = peerPnls.filter((p) => p < yourTotal).length
      const raw = (beaten / peerPnls.length) * 100
      percentileTopPct = Number.isFinite(raw)
        ? Math.min(100, Math.max(0, raw)).toFixed(1)
        : "0.0"
    }
  }

  return {
    chartData,
    todayStats: {
      yourTradeCount,
      yourAvgPnl,
      yourAvgRR,
      globalAvgPnl,
      globalAvgRR,
      globalTradeCount,
      percentileTopPct,
    },
    hasData: true,
  }
}
