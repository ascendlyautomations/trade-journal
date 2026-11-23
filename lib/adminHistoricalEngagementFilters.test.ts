import assert from "node:assert/strict"
import test from "node:test"
import {
  validateHistoricalEngagementQuery,
  type HistoricalEngagementQuery,
} from "./adminHistoricalEngagementFilters.ts"

test("validate preset 90 passes", () => {
  const q: HistoricalEngagementQuery = {
    preset: 90,
    customStartDate: null,
    customEndDate: null,
    activityFilter: "all",
  }
  assert.equal(validateHistoricalEngagementQuery(q, "2026-11-23").valid, true)
})

test("validate custom rejects future end", () => {
  const q: HistoricalEngagementQuery = {
    preset: "custom",
    customStartDate: "2026-11-01",
    customEndDate: "2026-12-01",
    activityFilter: "trading",
  }
  const result = validateHistoricalEngagementQuery(q, "2026-11-23")
  assert.equal(result.valid, false)
  assert.match(result.message ?? "", /future/i)
})

test("validate custom rejects inverted range", () => {
  const q: HistoricalEngagementQuery = {
    preset: "custom",
    customStartDate: "2026-11-20",
    customEndDate: "2026-11-10",
    activityFilter: "social",
  }
  assert.equal(validateHistoricalEngagementQuery(q, "2026-11-23").valid, false)
})