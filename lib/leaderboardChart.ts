/**
 * Leaderboard chart pipeline: EST-aligned buckets, stable sorting, aligned series.
 * Used by app/leaderboard/page.tsx — keep logic here, not scattered in JSX.
 */

export type LeaderboardView = "daily" | "weekly" | "monthly"

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

/** Week start Sunday (0), matching prior leaderboard behavior, on NY wall calendar. */
function weekStartYmd(ymd: string): string {
  const { y, m, day } = parseYmd(ymd)
  const t = Date.UTC(y, m - 1, day, 12, 0, 0)
  const dow = new Date(t).getUTCDay()
  return addDaysYmd(ymd, -dow)
}

function monthKeyFromYmd(ymd: string): string {
  const { y, m } = parseYmd(ymd)
  return `${y}-${String(m).padStart(2, "0")}`
}

function parseMonthKey(key: string): { y: number; m: number } {
  const [y, m] = key.split("-").map(Number)
  return { y, m }
}

function addOneMonth(y: number, m: number): { y: number; m: number } {
  let mm = m + 1
  let yy = y
  if (mm > 12) {
    mm = 1
    yy += 1
  }
  return { y: yy, m: mm }
}

function monthKeyCompare(a: string, b: string): number {
  return a.localeCompare(b)
}

function getTradeBucketId(
  createdAtIso: string,
  view: LeaderboardView
): { bucketId: string; sortKey: number } {
  const ymdNY = formatDateNY(createdAtIso)

  if (view === "daily") {
    const { y, m, day } = parseYmd(ymdNY)
    return { bucketId: ymdNY, sortKey: y * 10000 + m * 100 + day }
  }

  if (view === "weekly") {
    const ws = weekStartYmd(ymdNY)
    const { y, m, day } = parseYmd(ws)
    return { bucketId: `W:${ws}`, sortKey: y * 10000 + m * 100 + day }
  }

  const mk = monthKeyFromYmd(ymdNY)
  const { y, m } = parseMonthKey(mk)
  return { bucketId: `M:${mk}`, sortKey: y * 100 + m }
}

function labelForBucket(bucketId: string, view: LeaderboardView): string {
  if (view === "daily") {
    const { y, m, day } = parseYmd(bucketId)
    return `${m}/${day}/${y}`
  }
  if (view === "weekly") {
    const ws = bucketId.startsWith("W:") ? bucketId.slice(2) : bucketId
    const { y, m, day } = parseYmd(ws)
    return `Week ${m}/${day}/${y}`
  }
  const mk = bucketId.startsWith("M:") ? bucketId.slice(2) : bucketId
  const { y, m } = parseMonthKey(mk)
  return `${m}/${y}`
}

/** All bucket ids from min trade day through today (NY), inclusive. */
function enumerateBucketIds(
  view: LeaderboardView,
  minYmdNY: string,
  endYmdNY: string
): { bucketId: string; sortKey: number }[] {
  const out: { bucketId: string; sortKey: number }[] = []

  if (view === "daily") {
    let cur = minYmdNY
    while (ymdCompare(cur, endYmdNY) <= 0) {
      const { y, m, day } = parseYmd(cur)
      const sortKey = y * 10000 + m * 100 + day
      out.push({ bucketId: cur, sortKey })
      cur = addDaysYmd(cur, 1)
    }
    return out
  }

  if (view === "weekly") {
    let curWs = weekStartYmd(minYmdNY)
    const endWs = weekStartYmd(endYmdNY)
    while (ymdCompare(curWs, endWs) <= 0) {
      const { y, m, day } = parseYmd(curWs)
      const sortKey = y * 10000 + m * 100 + day
      out.push({ bucketId: `W:${curWs}`, sortKey })
      curWs = addDaysYmd(curWs, 7)
    }
    return out
  }

  let { y, m } = parseMonthKey(monthKeyFromYmd(minYmdNY))
  const endMk = monthKeyFromYmd(endYmdNY)
  while (true) {
    const mk = `${y}-${String(m).padStart(2, "0")}`
    if (monthKeyCompare(mk, endMk) > 0) break
    const bucketId = `M:${mk}`
    out.push({ bucketId, sortKey: y * 100 + m })
    ;({ y, m } = addOneMonth(y, m))
  }
  return out
}

type UserAgg = { pnl: number; rr: number; count: number }

function emptyUserMap(): Record<string, UserAgg> {
  return {}
}

/**
 * Build chart rows + today stats from raw trades.
 * - Buckets use America/New_York calendar (same idea as dashboard EST helpers).
 * - One code path for bucket ids (no double toEST / mismatched getKey).
 * - Timeline includes every bucket from earliest trade date through today (NY).
 * - Missing user in a bucket => you: 0 for that period (continuous line).
 * - Average is mean of **each user's total PnL in that bucket** (users with ≥1 trade there only).
 */
export function buildLeaderboardChartData(
  trades: TradeForLeaderboard[],
  view: LeaderboardView,
  userId: string | null
): { chartData: LeaderboardChartRow[]; todayStats: LeaderboardTodayStats } {
  const todayYmd = formatDateNY(new Date().toISOString())
  const { bucketId: todayBucketId } = getTradeBucketId(
    new Date().toISOString(),
    view
  )

  const byBucket: Record<string, Record<string, UserAgg>> = {}

  for (const t of trades) {
    if (!t?.created_at || !t.user_id) continue
    const { bucketId } = getTradeBucketId(t.created_at, view)
    if (!byBucket[bucketId]) byBucket[bucketId] = emptyUserMap()
    const m = byBucket[bucketId]
    if (!m[t.user_id]) {
      m[t.user_id] = { pnl: 0, rr: 0, count: 0 }
    }
    m[t.user_id].pnl += num(t.pnl)
    m[t.user_id].rr += num(t.rr)
    m[t.user_id].count += 1
  }

  let minYmd = todayYmd
  for (const t of trades) {
    if (!t?.created_at) continue
    const ymd = formatDateNY(t.created_at)
    if (ymdCompare(ymd, minYmd) < 0) minYmd = ymd
  }

  const bucketSequence = enumerateBucketIds(view, minYmd, todayYmd)

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
        label: labelForBucket(bucketId, view),
        sortKey,
        average,
        best,
        worst,
        you,
      }
    }
  )

  const yourTrades = trades.filter((t) => t.user_id === userId)
  const inToday = yourTrades.filter((t) => {
    const { bucketId } = getTradeBucketId(t.created_at, view)
    return bucketId === todayBucketId
  })

  const globalToday = trades.filter((t) => {
    const { bucketId } = getTradeBucketId(t.created_at, view)
    return bucketId === todayBucketId
  })

  const yourTradeCount = inToday.length
  const yourAvgPnl =
    yourTradeCount > 0
      ? inToday.reduce((s, t) => s + num(t.pnl), 0) / yourTradeCount
      : 0
  const yourAvgRR = averageValidRR(inToday)

  const globalTradeCount = globalToday.length
  const globalAvgPnl =
    globalTradeCount > 0
      ? globalToday.reduce((s, t) => s + num(t.pnl), 0) / globalTradeCount
      : 0
  const globalAvgRR = averageValidRR(globalToday)

  const todayMap = byBucket[todayBucketId] || emptyUserMap()

  const yourTotal = inToday.reduce((s, t) => s + num(t.pnl), 0)

  /**
   * "Top X%": fraction of *other* traders in this bucket whose period P&L sum
   * is strictly below yours (same bucket, same view). Self excluded from the
   * pool so solo traders do not read as 0%.
   */
  let percentileTopPct = "0.0"
  if (!userId) {
    percentileTopPct = "—"
  } else {
    const peerPnls = Object.entries(todayMap)
      .filter(([uid, u]) => uid !== userId && u.count > 0)
      .map(([, u]) => u.pnl)

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
  }
}
