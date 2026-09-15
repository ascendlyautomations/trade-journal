import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { normalizeAIGeneratedText } from "./normalizeAIGeneratedText.ts"

describe("normalizeAIGeneratedText", () => {
  it("replaces spaced em dashes with comma spacing", () => {
    const input = "You traded well today — your strongest session was the NY open."
    assert.equal(
      normalizeAIGeneratedText(input),
      "You traded well today, your strongest session was the NY open."
    )
  })

  it("handles leading and trailing spaced variants", () => {
    assert.equal(normalizeAIGeneratedText("A— next"), "A, next")
    assert.equal(normalizeAIGeneratedText("A —next"), "A, next")
  })

  it("handles tight em dashes between words", () => {
    assert.equal(normalizeAIGeneratedText("today—your"), "today, your")
  })

  it("collapses duplicate commas from em dash replacements", () => {
    assert.equal(normalizeAIGeneratedText("one — two — three"), "one, two, three")
  })

  it("leaves text without em dashes unchanged", () => {
    const plain = "Hold the plan. Size down if needed."
    assert.equal(normalizeAIGeneratedText(plain), plain)
  })
})
