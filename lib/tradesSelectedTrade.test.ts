import { describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  parseTradesSelectedTradeId,
  tradesPageFiltersToRevealTrade,
  tradesSelectedTradeHref,
  type TradesPageViewFilters,
} from "./tradesSelectedTrade.ts"

const BASE_FILTERS: TradesPageViewFilters = {
  accountFilter: "all",
  accountTypeFilter: "all",
  timeframe: "all",
  selectedDate: "",
  resultFilter: "all",
  showPublicOnly: false,
  customRangeStart: "",
  customRangeEnd: "",
}

const TRADE = {
  id: "trade-1",
  account_id: "acc-live",
  mode: "live",
  created_at: "2026-03-15T14:00:00.000Z",
  pnl: 120,
  is_public: false,
}

describe("tradesSelectedTradeHref", () => {
  it("passes the actual trade id, not a list index", () => {
    assert.equal(tradesSelectedTradeHref("abc-uuid"), "/trades?trade=abc-uuid")
    assert.equal(tradesSelectedTradeHref(""), "/trades")
  })
})

describe("parseTradesSelectedTradeId", () => {
  it("reads the trade query param", () => {
    assert.equal(
      parseTradesSelectedTradeId(new URLSearchParams("trade=abc-uuid")),
      "abc-uuid"
    )
    assert.equal(parseTradesSelectedTradeId("?edit=abc-uuid"), null)
  })
})

describe("tradesPageFiltersToRevealTrade", () => {
  it("leaves matching filters unchanged", () => {
    const next = tradesPageFiltersToRevealTrade(TRADE, BASE_FILTERS)
    assert.deepEqual(next, BASE_FILTERS)
  })

  it("widens account, mode, and timeframe when they would hide the trade", () => {
    const next = tradesPageFiltersToRevealTrade(TRADE, {
      ...BASE_FILTERS,
      accountFilter: "Other|50000|acc-other",
      accountTypeFilter: "eval",
      timeframe: "daily",
    })
    assert.equal(next.accountFilter, "all")
    assert.equal(next.accountTypeFilter, "all")
    assert.equal(next.timeframe, "all")
  })

  it("clears result, date, and public filters that exclude the trade", () => {
    const next = tradesPageFiltersToRevealTrade(TRADE, {
      ...BASE_FILTERS,
      resultFilter: "losses",
      selectedDate: "2026-01-01",
      showPublicOnly: true,
    })
    assert.equal(next.resultFilter, "all")
    assert.equal(next.selectedDate, "")
    assert.equal(next.showPublicOnly, false)
  })
})
