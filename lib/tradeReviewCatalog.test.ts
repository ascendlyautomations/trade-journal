import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  TRADE_PSYCHOLOGY_CUSTOM_TOKEN,
  resolveTradePsychologyValue,
  tradePsychologyPickerState,
} from "./tradeReviewCatalog.ts"

describe("tradeReviewCatalog psychology", () => {
  it("resolves preset emotion", () => {
    assert.equal(resolveTradePsychologyValue("Calm", ""), "Calm")
  })

  it("resolves custom emotion text", () => {
    assert.equal(
      resolveTradePsychologyValue(TRADE_PSYCHOLOGY_CUSTOM_TOKEN, "Impatient"),
      "Impatient"
    )
  })

  it("maps unknown stored value to custom picker state", () => {
    const state = tradePsychologyPickerState("Opening drive", [
      "Trending",
      "Volatile",
    ])
    assert.equal(state.selection, TRADE_PSYCHOLOGY_CUSTOM_TOKEN)
    assert.equal(state.custom, "Opening drive")
  })
})
