import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { formatMobileWebChartAxisUsd } from "./mobileWebAnalytics.ts"

describe("formatMobileWebChartAxisUsd", () => {
  it("compacts thousands for phone chart ticks", () => {
    assert.equal(formatMobileWebChartAxisUsd(0), "$0")
    assert.equal(formatMobileWebChartAxisUsd(850), "$850")
    assert.equal(formatMobileWebChartAxisUsd(1540), "$1.5k")
    assert.equal(formatMobileWebChartAxisUsd(12500), "$13k")
    assert.equal(formatMobileWebChartAxisUsd(-12500), "-$13k")
  })
})
