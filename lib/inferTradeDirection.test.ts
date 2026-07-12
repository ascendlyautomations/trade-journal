import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  inferTradeDirectionFromPrices,
  nextDirectionAfterPriceChange,
  parseTradePriceInput,
} from "./inferTradeDirection.ts"

describe("inferTradeDirectionFromPrices", () => {
  it("selects Long when exit is higher than entry", () => {
    assert.equal(inferTradeDirectionFromPrices(20000, 20100), "Long")
  })

  it("selects Short when exit is lower than entry", () => {
    assert.equal(inferTradeDirectionFromPrices(20100, 20000), "Short")
  })

  it("does not infer when prices are equal", () => {
    assert.equal(inferTradeDirectionFromPrices(20000, 20000), null)
  })

  it("does not infer when either price is missing", () => {
    assert.equal(inferTradeDirectionFromPrices(20000, null), null)
    assert.equal(inferTradeDirectionFromPrices(null, 20100), null)
    assert.equal(inferTradeDirectionFromPrices(undefined, undefined), null)
  })
})

describe("nextDirectionAfterPriceChange", () => {
  it("auto-updates while not manually overridden", () => {
    assert.equal(
      nextDirectionAfterPriceChange({
        current: "Short",
        manualOverride: false,
        entryPrice: 100,
        exitPrice: 110,
      }),
      "Long"
    )
    assert.equal(
      nextDirectionAfterPriceChange({
        current: "Long",
        manualOverride: false,
        entryPrice: 110,
        exitPrice: 100,
      }),
      "Short"
    )
  })

  it("preserves manual Long after price edits", () => {
    assert.equal(
      nextDirectionAfterPriceChange({
        current: "Long",
        manualOverride: true,
        entryPrice: 110,
        exitPrice: 100,
      }),
      "Long"
    )
  })

  it("preserves manual Short after price edits", () => {
    assert.equal(
      nextDirectionAfterPriceChange({
        current: "Short",
        manualOverride: true,
        entryPrice: 100,
        exitPrice: 110,
      }),
      "Short"
    )
  })

  it("preserves direction when one price is cleared", () => {
    assert.equal(
      nextDirectionAfterPriceChange({
        current: "Short",
        manualOverride: false,
        entryPrice: 100,
        exitPrice: null,
      }),
      "Short"
    )
  })

  it("infers again when both prices return and no manual override", () => {
    assert.equal(
      nextDirectionAfterPriceChange({
        current: "Long",
        manualOverride: false,
        entryPrice: 110,
        exitPrice: 100,
      }),
      "Short"
    )
  })
})

describe("parseTradePriceInput", () => {
  it("parses currency-formatted prices", () => {
    assert.equal(parseTradePriceInput("$20,100.5"), 20100.5)
    assert.equal(parseTradePriceInput(""), null)
  })
})
