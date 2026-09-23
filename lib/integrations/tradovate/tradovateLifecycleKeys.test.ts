import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { filterPreviewsNotInBaseline } from "./tradovateLifecycleKeys.ts"

describe("tradovate lifecycle preview baseline", () => {
  it("uses sync-start snapshot so concurrent import cannot zero preview", () => {
    const previews = [
      { lifecycleKey: "tradovate:v2:1:4399654:3" },
      { lifecycleKey: "tradovate:v2:1:4399654:4" },
    ]
    const atStart = new Set(["tradovate:v2:1:4399654:3"])
    const eligible = filterPreviewsNotInBaseline(previews, atStart)
    assert.equal(eligible.length, 1)
    assert.equal(eligible[0]!.lifecycleKey, "tradovate:v2:1:4399654:4")
  })
})
