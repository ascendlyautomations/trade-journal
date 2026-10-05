import assert from "node:assert/strict"
import test from "node:test"
import {
  copyTradeBatchKey,
  copyTradeParticipatingAccountIds,
  dedupeCopyTradeFeedPosts,
  formatCopyTradePublicModeSummary,
  formatCopyTradePublicModeSummaryFromTrades,
  groupTradesForTradesPageDisplay,
  tradeMatchesParticipatingAccountFilter,
} from "./copyTradePresentation.ts"

test("participating account ids include source and destinations", () => {
  const ids = copyTradeParticipatingAccountIds({
    trade_mode: "copy_traded",
    source_account_id: "a",
    copied_account_ids: ["b", "c"],
    account_id: "b",
  })
  assert.deepEqual(new Set(ids), new Set(["a", "b", "c"]))
})

test("account filter matches any participating copy account", () => {
  const trade = {
    trade_mode: "copy_traded",
    source_account_id: "a",
    copied_account_ids: ["b"],
    account_id: "b",
  }
  assert.equal(tradeMatchesParticipatingAccountFilter(trade, "a"), true)
  assert.equal(tradeMatchesParticipatingAccountFilter(trade, "b"), true)
  assert.equal(tradeMatchesParticipatingAccountFilter(trade, "z"), false)
})

test("public mode summary from grouped siblings counts each account mode", () => {
  const base = {
    user_id: "u1",
    trade_mode: "copy_traded",
    source_account_id: "a",
    copied_account_ids: ["b", "c"],
    ticker: "NQ",
    entry_time: "2026-01-01T12:00:00Z",
  }
  const line = formatCopyTradePublicModeSummaryFromTrades([
    { ...base, id: "t1", account_id: "a", mode: "copy_traded", account_mode: "funded" },
    { ...base, id: "t2", account_id: "b", mode: "funded" },
    { ...base, id: "t3", account_id: "c", mode: "funded", account_mode: "eval" },
  ])
  assert.equal(line, "Copy Traded across 3 accounts • 2 Funded • 1 Eval")
})

test("public mode summary omits zero counts", () => {
  const line = formatCopyTradePublicModeSummary(
    {
      live: 1,
      funded: 2,
      eval: 1,
      sim: 0,
      backtest: 0,
    },
    4
  )
  assert.equal(
    line,
    "Copy Traded across 4 accounts • 1 Live • 2 Funded • 1 Eval"
  )
})

test("trades page groups copy siblings into one card", () => {
  const base = {
    user_id: "u1",
    trade_mode: "copy_traded",
    source_account_id: "a",
    copied_account_ids: ["b"],
    ticker: "NQ",
    entry_time: "2026-01-01T12:00:00Z",
    created_at: "2026-01-01T12:00:01Z",
  }
  const items = groupTradesForTradesPageDisplay([
    { ...base, id: "t1", account_id: "a", mode: "funded" },
    { ...base, id: "t2", account_id: "b", mode: "live" },
    { id: "solo", trade_mode: "live", account_id: "x", user_id: "u1", created_at: "2026-01-02" },
  ])
  assert.equal(items.length, 2)
  assert.equal(items[0].kind, "copyGroup")
  assert.equal(items[1].kind, "single")
})

test("batch key ignores created_at when authoritative copy stamp is present", () => {
  const base = {
    trade_mode: "copy_traded",
    source_account_id: "a",
    copied_account_ids: ["b", "c"],
    user_id: "u",
    ticker: "NQ",
    entry_time: "2026-01-01T12:00:00Z",
  }
  const k1 = copyTradeBatchKey({
    ...base,
    account_id: "a",
    created_at: "2026-01-01T12:00:01Z",
  })
  const k2 = copyTradeBatchKey({
    ...base,
    account_id: "b",
    created_at: "2026-01-01T12:00:09Z",
  })
  assert.ok(k1)
  assert.equal(k1, k2)
})

test("dedupe feed posts by copy batch key", () => {
  const trade = {
    trade_mode: "copy_traded",
    source_account_id: "a",
    copied_account_ids: ["b"],
    account_id: "a",
    user_id: "u",
    created_at: "2026-01-01T12:00:00Z",
    ticker: "ES",
    entry_time: "2026-01-01T12:00:00Z",
  }
  const key = copyTradeBatchKey(trade)
  assert.ok(key)
  const posts = dedupeCopyTradeFeedPosts([
    { id: "p1", trades: trade },
    { id: "p2", trades: { ...trade, account_id: "b" } },
  ])
  assert.equal(posts.length, 1)
})
