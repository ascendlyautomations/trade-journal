import { describe, it } from "node:test"
import assert from "node:assert/strict"
import type { TradesPageListItem } from "./copyTradePresentation.ts"
import {
  buildMobileWebTradesChips,
  hasMobileWebTradeScreenshot,
  mobileWebJournalPointsLabel,
  mobileWebJournalRrLabel,
  mobileWebTradeThumbHeightPx,
  sortTradeListItemsForMobileWeb,
  tradeListItemMatchesMobileWebSearch,
  tradeMatchesMobileWebSearch,
} from "./mobileWebTradesPresentation.ts"

describe("mobileWebTradesPresentation", () => {
  it("clamps journal thumbnail height to native 36–120pt", () => {
    assert.equal(mobileWebTradeThumbHeightPx(96, 96), 96)
    assert.equal(mobileWebTradeThumbHeightPx(96, 240), 120)
    assert.equal(mobileWebTradeThumbHeightPx(192, 96), 48)
    assert.equal(mobileWebTradeThumbHeightPx(400, 40), 36)
  })

  it("does not treat blank screenshot URLs as present", () => {
    assert.equal(hasMobileWebTradeScreenshot(null), false)
    assert.equal(hasMobileWebTradeScreenshot(""), false)
    assert.equal(hasMobileWebTradeScreenshot("  "), false)
    assert.equal(hasMobileWebTradeScreenshot("/shots/nq.png"), true)
  })

  it("formats journal R:R and omits missing values", () => {
    assert.equal(mobileWebJournalRrLabel(2.9), "1:2.9")
    assert.equal(mobileWebJournalRrLabel(null), null)
    assert.equal(mobileWebJournalRrLabel(""), null)
  })

  it("formats journal points and omits missing values", () => {
    assert.equal(
      mobileWebJournalPointsLabel({ points: 21.75, direction: "Long" }),
      "21.75"
    )
    assert.equal(mobileWebJournalPointsLabel({ points: null }), null)
  })

  it("matches ticker, notes, and session in search", () => {
    const trade = { ticker: "NQ", notes: "open drive", session: "NY AM" }
    assert.equal(tradeMatchesMobileWebSearch(trade, "nq"), true)
    assert.equal(tradeMatchesMobileWebSearch(trade, "drive"), true)
    assert.equal(tradeMatchesMobileWebSearch(trade, "ny"), true)
    assert.equal(tradeMatchesMobileWebSearch(trade, "es"), false)
    assert.equal(tradeMatchesMobileWebSearch(trade, "  "), true)
  })

  it("matches any member of a copy group", () => {
    const item: TradesPageListItem = {
      kind: "copyGroup",
      batchKey: "batch-1",
      representative: { id: "1", ticker: "ES" },
      members: [{ id: "1", ticker: "ES" }, { id: "2", ticker: "NQ" }],
      modeSummary: null,
    }
    assert.equal(tradeListItemMatchesMobileWebSearch(item, "nq"), true)
    assert.equal(tradeListItemMatchesMobileWebSearch(item, "cl"), false)
  })

  it("sorts list items by representative P&L without mutating source", () => {
    const items: TradesPageListItem[] = [
      {
        kind: "single",
        trade: { id: "a", created_at: "2026-01-02" },
      },
      {
        kind: "single",
        trade: { id: "b", created_at: "2026-01-01" },
      },
    ]
    ;(items[0] as { trade: { pnl?: number } }).trade.pnl = 10
    ;(items[1] as { trade: { pnl?: number } }).trade.pnl = 40
    const sorted = sortTradeListItemsForMobileWeb(items, "pnl_high")
    assert.equal(
      sorted[0] && sorted[0].kind === "single" ? sorted[0].trade.id : null,
      "b"
    )
    assert.equal(
      items[0] && items[0].kind === "single" ? items[0].trade.id : null,
      "a"
    )
  })

  it("builds dismissible chips only for active filters", () => {
    assert.deepEqual(
      buildMobileWebTradesChips({
        search: "",
        accountFilter: "all",
        accountTypeFilter: "all",
        timeframe: "all",
        selectedDate: "",
        resultFilter: "all",
        showPublicOnly: false,
        sortBy: "newest",
      }),
      []
    )

    const chips = buildMobileWebTradesChips({
      search: "NQ",
      accountFilter: "acct-1",
      accountLabel: "Apex 50k",
      accountTypeFilter: "funded",
      timeframe: "weekly",
      selectedDate: "",
      resultFilter: "wins",
      showPublicOnly: true,
      sortBy: "pnl_high",
    })
    assert.deepEqual(
      chips.map((chip) => chip.id),
      ["search", "account", "mode", "timeframe", "result", "public", "sort"]
    )
    assert.equal(chips.find((chip) => chip.id === "account")?.title, "Apex 50k")
    assert.equal(chips.find((chip) => chip.id === "timeframe")?.title, "This Week")
  })
})

export {}
