import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  fallbackFuturesValuePerPoint,
  resolveEffectiveValuePerPoint,
} from "./futuresValuePerPointFallback.ts"

describe("futuresValuePerPointFallback", () => {
  it("prefers contract metadata when present", () => {
    assert.equal(
      resolveEffectiveValuePerPoint({
        symbolRoot: "MNQ",
        contractValuePerPoint: 2.5,
      }),
      2.5
    )
  })

  it("falls back from normalized root when contract metadata missing", () => {
    assert.equal(
      resolveEffectiveValuePerPoint({
        symbolRoot: "MNQM6",
        contractValuePerPoint: null,
      }),
      2
    )
    assert.equal(fallbackFuturesValuePerPoint("ESZ25"), 50)
  })

  it("returns null when symbol is unknown", () => {
    assert.equal(fallbackFuturesValuePerPoint("UNKNOWNXYZ"), null)
  })
})
