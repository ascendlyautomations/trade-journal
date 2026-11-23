import assert from "node:assert/strict"
import test from "node:test"
import { retentionRateLabel } from "./adminProductAnalytics.ts"

test("sumSeriesCounts totals daily points", () => {
  const sum = (points: { count: number }[]) =>
    points.reduce((acc, p) => acc + (Number.isFinite(p.count) ? p.count : 0), 0)
  assert.equal(
    sum([
      { count: 2 },
      { count: 3 },
    ]),
    5
  )
})

test("historicalRetentionRateLabel mirrors product retention labels", () => {
  const historicalRetentionRateLabel = (
    rate: number | null | undefined,
    matureCohortSize: number,
    insufficientData: boolean
  ) => retentionRateLabel(rate, matureCohortSize, insufficientData)

  assert.equal(historicalRetentionRateLabel(null, 0, true), "Insufficient data")
  assert.equal(historicalRetentionRateLabel(12.5, 8, false), "12.5%")
})