const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  buildCommunitySharePreviewPost,
} = require("./buildCommunitySharePreviewPost.ts")
const {
  resolveFeedTradeAccountType,
} = require("./feedAccountType.ts")

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

    assert.equal(post.trades.account_type, "live")
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

    assert.equal(post.trades.account_type, "eval")
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

    assert.equal(post.trades.entry_time, entry)
    assert.equal(post.trades.exit_time, exit)
    assert.equal(post.trades.entry_price, 23456)
    assert.equal(post.trades.exit_price, 23458)
    assert.equal(post.trades.trade_date, "2026-06-02")
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

    assert.equal(post.trades.reels?.id, "community-preview-reel")
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

    assert.equal(post.trades.reels, undefined)
  })
})
