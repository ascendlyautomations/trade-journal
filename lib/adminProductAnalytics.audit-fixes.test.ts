import assert from "node:assert/strict"
import test from "node:test"
import {
  productActiveChartData,
  retentionRateLabel,
  type AdminProductAnalyticsBundle,
} from "./adminProductAnalytics.ts"

test("productActiveChartData omits null pre-tracking counts", () => {
  const points = [
    { day: "2026-11-20", count: null },
    { day: "2026-11-21", count: 0 },
    { day: "2026-11-22", count: 2 },
  ]
  assert.deepEqual(productActiveChartData(points), [
    { day: "2026-11-21", count: 0 },
    { day: "2026-11-22", count: 2 },
  ])
})

test("retentionRateLabel shows insufficient when cohort immature", () => {
  assert.equal(retentionRateLabel(50, 0, true), "Insufficient data")
  assert.equal(retentionRateLabel(null, 10, false), "—")
  assert.equal(retentionRateLabel(42.5, 12, false), "42.5%")
})

test("import totals type includes manualEntered split", () => {
  const totals: AdminProductAnalyticsBundle["trading"]["importTotalsInPeriod"] = {
    manualEntered: 40,
    unsetImportSource: 16,
    csv: 0,
    broker: 0,
    other: 0,
  }
  assert.equal(totals.manualEntered + totals.unsetImportSource, 56)
})