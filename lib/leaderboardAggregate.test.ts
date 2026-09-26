import { describe, it } from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import {
  buildLeaderboardRankings,
  filterTradesForLeaderboardAccountType,
  filterTradesForLeaderboardWindow,
  type TradeForLeaderboard,
} from "./leaderboardChart.ts"
import {
  LEADERBOARD_RANK_LIMIT,
  buildLeaderboardPayloadFromTrades,
  rankLeaderboardTraders,
} from "./leaderboardAggregate.ts"
import { buildLeaderboardChartDataWithFallback } from "./leaderboardTimeframeFallback.ts"

const NOW = new Date("2026-09-24T15:00:00.000Z")

function trade(
  userId: string,
  pnl: number | null,
  iso: string,
  extra: Partial<TradeForLeaderboard> = {}
): TradeForLeaderboard {
  return {
    user_id: userId,
    pnl,
    rr: extra.rr ?? 1,
    created_at: iso,
    ...extra,
  }
}

describe("leaderboard aggregation parity", () => {
  it("ranks by total P&L descending and matches the old client ranking", () => {
    const trades = [
      trade("low", 10, "2026-09-01T00:00:00.000Z"),
      trade("high", 40, "2026-09-02T00:00:00.000Z"),
      trade("high", 5, "2026-09-03T00:00:00.000Z"),
      trade("mid", 20, "2026-09-04T00:00:00.000Z"),
    ]
    const old = buildLeaderboardRankings(trades, Number.POSITIVE_INFINITY)
    const next = rankLeaderboardTraders(trades, Number.POSITIVE_INFINITY)
    assert.deepEqual(
      next.map((row) => row.userId),
      old.map((row) => row.userId)
    )
    assert.deepEqual(
      next.map((row) => row.totalPnl),
      [45, 20, 10]
    )
    assert.deepEqual(
      next.map((row) => row.tradeCount),
      [2, 1, 1]
    )
  })

  it("breaks equal P&L by earliest trade, then user id", () => {
    const trades = [
      trade("b-user", 10, "2026-09-02T00:00:00.000Z"),
      trade("a-user", 10, "2026-09-02T00:00:00.000Z"),
      trade("early", 10, "2026-09-01T00:00:00.000Z"),
    ]
    const ordered = [...trades].sort((a, b) => {
      const at = new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
      if (at !== 0) return at
      return String(a.user_id).localeCompare(String(b.user_id))
    })
    const old = buildLeaderboardRankings(ordered, Number.POSITIVE_INFINITY)
    const next = rankLeaderboardTraders(trades, Number.POSITIVE_INFINITY)
    assert.deepEqual(
      next.map((row) => [row.rank, row.userId]),
      old.map((row) => [row.rank, row.userId])
    )
    assert.deepEqual(
      next.map((row) => row.userId),
      ["early", "a-user", "b-user"]
    )
  })

  it("does not rank a wins-only trader above a higher P&L trader", () => {
    const trades = [
      trade("wins-only", 10, "2026-09-01T00:00:00.000Z", { rr: 5 }),
      trade("wins-only", 10, "2026-09-02T00:00:00.000Z", { rr: 5 }),
      trade("higher-pnl", 100, "2026-09-03T00:00:00.000Z", { rr: 0.2 }),
      trade("higher-pnl", -40, "2026-09-04T00:00:00.000Z", { rr: null }),
    ]
    const ranked = rankLeaderboardTraders(trades, Number.POSITIVE_INFINITY)
    assert.equal(ranked[0].userId, "higher-pnl")
    assert.equal(ranked[0].totalPnl, 60)
    assert.equal(ranked[1].userId, "wins-only")
    assert.equal(ranked[1].avgRR, 5)
    assert.equal(ranked[0].avgRR, 0.2)
  })

  it("does not use win rate as a ranking key", () => {
    const trades = [
      trade("perfect", 5, "2026-09-01T00:00:00.000Z"),
      trade("mixed", 50, "2026-09-02T00:00:00.000Z"),
      trade("mixed", -10, "2026-09-03T00:00:00.000Z"),
    ]
    const ranked = rankLeaderboardTraders(trades, Number.POSITIVE_INFINITY)
    assert.equal(ranked[0].userId, "mixed")
    assert.equal(ranked[0].totalPnl, 40)
  })

  it("treats null P&L as zero and excludes null RR from the average", () => {
    const trades = [
      trade("a", null, "2026-09-01T00:00:00.000Z", { rr: null }),
      trade("a", 8, "2026-09-02T00:00:00.000Z", { rr: 2 }),
      trade("b", 8, "2026-09-03T00:00:00.000Z", { rr: 0 }),
    ]
    const ranked = rankLeaderboardTraders(trades, Number.POSITIVE_INFINITY)
    const a = ranked.find((row) => row.userId === "a")
    const b = ranked.find((row) => row.userId === "b")
    assert.equal(a?.totalPnl, 8)
    assert.equal(a?.avgRR, 2)
    assert.equal(b?.avgRR, 0)
    assert.equal(a?.tradeCount, 2)
  })

  it("keeps a trader with no valid RR behind the same P&L only by tie-break, not by a missing factor", () => {
    const trades = [
      trade("no-rr", 15, "2026-09-02T00:00:00.000Z", { rr: null }),
      trade("has-rr", 15, "2026-09-01T00:00:00.000Z", { rr: 1 }),
    ]
    const ranked = rankLeaderboardTraders(trades, Number.POSITIVE_INFINITY)
    assert.equal(ranked[0].userId, "has-rr")
    assert.equal(ranked[1].avgRR, null)
    assert.ok(ranked[1].totalPnl <= ranked[0].totalPnl)
  })

  it("drops trades outside the 7 day window before ranking", () => {
    const recent = new Date(NOW.getTime() - 2 * 24 * 60 * 60 * 1000).toISOString()
    const old = new Date(NOW.getTime() - 20 * 24 * 60 * 60 * 1000).toISOString()
    const trades = [
      trade("recent", 10, recent),
      trade("stale", 500, old),
    ]
    const windowed = filterTradesForLeaderboardWindow(trades, "7D", NOW)
    const ranked = rankLeaderboardTraders(windowed, Number.POSITIVE_INFINITY)
    assert.deepEqual(
      ranked.map((row) => row.userId),
      ["recent"]
    )
  })

  it("applies the account filter before the window", () => {
    const iso = new Date(NOW.getTime() - 60 * 60 * 1000).toISOString()
    const trades = [
      trade("live-user", 30, iso, { mode: "live" }),
      trade("eval-user", 80, iso, { mode: "eval" }),
    ]
    const filtered = filterTradesForLeaderboardAccountType(trades, "live")
    const payload = buildLeaderboardPayloadFromTrades(filtered, {
      view: "ALL",
      accountType: "all",
      nowIso: NOW.toISOString(),
    })
    assert.deepEqual(
      payload.rankedTraders.map((row) => row.userId),
      ["live-user"]
    )
  })

  it("returns an empty ranking when nobody has trades", () => {
    const payload = buildLeaderboardPayloadFromTrades([], {
      view: "7D",
      accountType: "all",
      nowIso: NOW.toISOString(),
      viewerId: "viewer",
    })
    assert.equal(payload.hasData, false)
    assert.deepEqual(payload.rankedTraders, [])
    assert.equal(payload.yourRank, null)
    assert.equal(payload.todayStats.globalTradeCount, 0)
  })

  it("caps the rendered ranking at 25 and matches the old chart pipeline", () => {
    const trades = Array.from({ length: 30 }, (_, index) =>
      trade(`u-${String(index).padStart(2, "0")}`, index + 1, `2026-09-${String((index % 28) + 1).padStart(2, "0")}T00:00:00.000Z`)
    )
    const payload = buildLeaderboardPayloadFromTrades(trades, {
      view: "ALL",
      accountType: "all",
      nowIso: NOW.toISOString(),
      viewerId: "u-29",
    })
    const old = buildLeaderboardChartDataWithFallback(
      trades,
      "ALL",
      "u-29",
      undefined,
      "all"
    )
    assert.equal(payload.rankedTraders.length, LEADERBOARD_RANK_LIMIT)
    assert.equal(payload.rankedTraders.length, 25)
    assert.deepEqual(
      payload.rankedTraders.map((row) => [row.rank, row.userId, row.totalPnl]),
      old.rankedTraders.map((row) => [row.rank, row.userId, row.totalPnl])
    )
    assert.equal(payload.yourRank?.rank, old.yourRank?.rank)
    assert.equal(payload.yourRank?.totalTraders, 30)
    assert.equal(payload.chartData.length, old.chartData.length)
    assert.equal(payload.todayStats.globalTradeCount, old.todayStats.globalTradeCount)
  })

  it("keeps public-trade visibility and a bounded rank in the SQL contract", () => {
    const sql = fs.readFileSync(
      path.join(
        path.dirname(fileURLToPath(import.meta.url)),
        "../supabase/migrations/20260931140000_leaderboard_ranked_window.sql"
      ),
      "utf8"
    )
    assert.match(sql, /coalesce\(t\.is_public, false\) = true/)
    assert.match(sql, /coalesce\(pr\.is_private, false\) = false/)
    assert.match(sql, /order by total_pnl desc, first_trade_at asc, user_id asc/)
    assert.match(sql, /rank <= b\.rank_limit/)
    assert.match(sql, /least\(coalesce\(p_rank_limit, 25\), 25\)/)
    assert.doesNotMatch(sql, /notes/)
    assert.doesNotMatch(sql, /entry_price/)
    const route = fs.readFileSync(
      path.join(path.dirname(fileURLToPath(import.meta.url)), "../app/api/leaderboard/trades/route.ts"),
      "utf8"
    )
    assert.match(route, /leaderboard_ranked_window/)
    assert.match(route, /NextResponse\.json\(payload\)/)
    assert.doesNotMatch(route, /NextResponse\.json\(trades\)/)
  })
})
