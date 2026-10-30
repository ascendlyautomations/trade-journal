import assert from "node:assert/strict"
import { describe, it, beforeEach } from "node:test"
import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "./database.types.ts"
import type { TradeForLeaderboard } from "./leaderboardChart.ts"
import { paginateLeaderboardTradeRows } from "./leaderboardTradeRowsPaginate.ts"
import {
  __resetLeaderboardTradeRowsFlightsForTests,
  withLeaderboardTradeRowsSingleFlight,
} from "./leaderboardTradeRowsSingleFlight.ts"

function trade(userId: string, createdAt: string): TradeForLeaderboard {
  return { user_id: userId, created_at: createdAt, pnl: 10, rr: 1 }
}

function mockClient(
  handler: (
    args: Record<string, unknown>,
    attempt: number
  ) => Promise<{ data: TradeForLeaderboard[] | null; error: null }>
): SupabaseClient<Database> {
  let attempt = 0
  return {
    rpc: async (_name, args, _opts) => {
      attempt += 1
      return handler(args as Record<string, unknown>, attempt)
    },
  } as unknown as SupabaseClient<Database>
}

describe("leaderboard trade rows fetch resilience", () => {
  beforeEach(() => {
    __resetLeaderboardTradeRowsFlightsForTests()
  })

  it("recovers leaderboard page after transient socket disconnect", async () => {
    let rpcCalls = 0
    const client = mockClient(async () => {
      rpcCalls += 1
      if (rpcCalls === 1) {
        throw new TypeError("fetch failed", {
          cause: { code: "UND_ERR_SOCKET" },
        })
      }
      return {
        data: [trade("u1", "2026-10-01T12:00:00.000Z")],
        error: null,
      }
    })

    const { trades, partial } = await paginateLeaderboardTradeRows(client, {
      maxRows: 10,
      operation: "test_leaderboard_recover",
    })
    assert.equal(partial, false)
    assert.equal(trades.length, 1)
    assert.equal(trades[0]?.user_id, "u1")
    assert.ok(rpcCalls >= 2)
  })

  it("returns partial rows when a later page never succeeds", async () => {
    let page = 0
    const client = mockClient(async (args) => {
      const after = args.p_after_created_at
      if (!after) {
        page += 1
        return {
          data: Array.from({ length: 1000 }, (_, i) =>
            trade(`u${i}`, `2026-10-01T12:${String(i % 60).padStart(2, "0")}:00.000Z`)
          ),
          error: null,
        }
      }
      throw new TypeError("fetch failed", {
        cause: { code: "UND_ERR_SOCKET" },
      })
    })

    const { trades, partial } = await paginateLeaderboardTradeRows(client, {
      maxRows: 2500,
      operation: "test_leaderboard_partial",
      pageTimeoutMs: 5_000,
    })
    assert.equal(partial, true)
    assert.equal(trades.length, 1000)
    assert.ok(page >= 1)
  })

  it("dedupes concurrent in-flight server scans", async () => {
    let starts = 0
    const p1 = withLeaderboardTradeRowsSingleFlight("maxRows:100", async () => {
      starts += 1
      await new Promise((r) => setTimeout(r, 40))
      return [trade("u1", "2026-10-01T12:00:00.000Z")]
    })
    const p2 = withLeaderboardTradeRowsSingleFlight("maxRows:100", async () => {
      starts += 1
      return [trade("u2", "2026-10-02T12:00:00.000Z")]
    })
    const [a, b] = await Promise.all([p1, p2])
    assert.equal(starts, 1)
    assert.deepEqual(a, b)
  })
})
