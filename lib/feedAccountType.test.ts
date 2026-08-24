import { describe, it } from "node:test"
import { buildCommunitySharePreviewPost, } from "./buildCommunitySharePreviewPost.ts"
import { resolveFeedTradeAccountType, } from "./feedAccountType.ts"
import assert from "node:assert/strict"

type CommunitySharePreviewTradeJoin = {
  account_type?: string
  entry_time?: string | null
  exit_time?: string | null
  entry_price?: number | null
  exit_price?: number | null
  trade_date?: string | null
  reels?: { id?: string }
}

function previewTrades(post: Record<string, unknown>): CommunitySharePreviewTradeJoin {
  const trades = post.trades
  assert.ok(trades && typeof trades === "object" && !Array.isArray(trades))
  return trades as CommunitySharePreviewTradeJoin
}

describe("resolveFeedTradeAccountType", () => {
  it("defaults missing mode to live", () => {
    assert.equal(resolveFeedTradeAccountType({}), "live")
    assert.equal(resolveFeedTradeAccountType({ mode: null }), "live")
    assert.equal(resolveFeedTradeAccountType({ mode: "" }), "live")
  })

  it("normalizes eval and funded", () => {
    assert.equal(resolveFeedTradeAccountType({ mode: "Eval" }), "eval")
    assert.equal(resolveFeedTradeAccountType({ mode: "Funded" }), "funded")
    assert.equal(resolveFeedTradeAccountType({ mode: "Live" }), "live")
  })

  it("uses locked account type for free users", () => {
    assert.equal(
      resolveFeedTradeAccountType({
        mode: "live",
        lockedAccountType: "eval",
        isPro: false,
      }),
      "eval"
    )
  })

  it("does not apply locked type for pro users", () => {
    assert.equal(
      resolveFeedTradeAccountType({
        mode: null,
        lockedAccountType: "eval",
        isPro: true,
      }),
      "live"
    )
  })
})

describe("buildCommunitySharePreviewPost", () => {
  it("includes live badge source when account mode is missing", () => {
    const post = buildCommunitySharePreviewPost({
      userId: "user-1",
      username: "trader",
      avatarUrl: null,
      pnl: 100,
      rr: 2,
      points: 10,
      ticker: "NQ",
      direction: "Long",
      accountMode: null,
      isPro: true,
      publicDescription: "Test",
      imageUrl: null,
    })

    assert.equal(previewTrades(post).account_type, "live")
  })

  it("matches eval account type in preview trades join", () => {
    const post = buildCommunitySharePreviewPost({
      userId: "user-1",
      username: "trader",
      avatarUrl: null,
      pnl: 100,
      rr: 2,
      points: 10,
      ticker: "NQ",
      direction: "Long",
      accountMode: "eval",
      isPro: true,
      publicDescription: "Test",
      imageUrl: null,
    })

    assert.equal(previewTrades(post).account_type, "eval")
  })

  it("includes trade timing metadata for TradeCardTimingBlock", () => {
    const entry = new Date("2026-06-02T14:40:00").toISOString()
    const exit = new Date("2026-06-08T13:40:00").toISOString()
    const post = buildCommunitySharePreviewPost({
      userId: "user-1",
      username: "trader",
      avatarUrl: null,
      pnl: 100,
      rr: 2,
      points: 10,
      ticker: "NQ",
      direction: "Long",
      accountMode: "live",
      isPro: true,
      publicDescription: "Test",
      imageUrl: null,
      entryTime: entry,
      exitTime: exit,
      entryPrice: 23456,
      exitPrice: 23458,
      tradeDate: "2026-06-02",
    })

    const trades = previewTrades(post)
    assert.equal(trades.entry_time, entry)
    assert.equal(trades.exit_time, exit)
    assert.equal(trades.entry_price, 23456)
    assert.equal(trades.exit_price, 23458)
    assert.equal(trades.trade_date, "2026-06-02")
  })

  it("embeds trades.reels so Feed View Clip badge can render", () => {
    const post = buildCommunitySharePreviewPost({
      userId: "user-1",
      username: "trader",
      avatarUrl: null,
      pnl: 100,
      rr: 2,
      points: 10,
      ticker: "NQ",
      direction: "Long",
      accountMode: "live",
      isPro: true,
      publicDescription: "Test",
      imageUrl: null,
      attachedReel: true,
    })

    assert.equal(previewTrades(post).reels?.id, "community-preview-reel")
  })

  it("omits trades.reels when no clip is attached", () => {
    const post = buildCommunitySharePreviewPost({
      userId: "user-1",
      username: "trader",
      avatarUrl: null,
      pnl: 100,
      rr: 2,
      points: 10,
      ticker: "NQ",
      direction: "Long",
      accountMode: "live",
      isPro: true,
      publicDescription: "Test",
      imageUrl: null,
    })

    assert.equal(previewTrades(post).reels, undefined)
  })
})
export {}
