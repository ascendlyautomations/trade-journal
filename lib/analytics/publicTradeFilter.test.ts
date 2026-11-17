import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { applyPublicVisibilityFilter } from "./publicTradeFilter.ts"

describe("applyPublicVisibilityFilter", () => {
  const trades = [
    { id: "private", is_public: false },
    { id: "public", is_public: true },
  ]

  it("keeps every trade when public-only is off", () => {
    const next = applyPublicVisibilityFilter(trades, false, (trade) => trade.is_public)
    assert.deepEqual(
      next.map((trade) => trade.id),
      ["private", "public"]
    )
  })

  it("returns an empty list when public-only is on and nothing is public", () => {
    const next = applyPublicVisibilityFilter(
      [{ id: "private", is_public: false }],
      true,
      (trade) => trade.is_public
    )
    assert.deepEqual(next, [])
  })

  it("keeps only public trades when some are public", () => {
    const next = applyPublicVisibilityFilter(trades, true, (trade) => trade.is_public)
    assert.deepEqual(
      next.map((trade) => trade.id),
      ["public"]
    )
  })
})
