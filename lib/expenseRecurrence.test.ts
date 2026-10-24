import assert from "node:assert/strict"
import test from "node:test"
import { occurrenceDates } from "./expenseRecurrence.ts"

test("weekly recurrence lists every date from the start through today", () => {
  assert.deepEqual(occurrenceDates("2026-10-01", "weekly", "2026-10-15"), [
    "2026-10-01",
    "2026-10-08",
    "2026-10-15",
  ])
})

test("monthly recurrence keeps the anchor day and clamps short months", () => {
  assert.deepEqual(occurrenceDates("2024-01-31", "monthly", "2024-03-31"), [
    "2024-01-31",
    "2024-02-29",
    "2024-03-31",
  ])
})

test("yearly recurrence and future dates stay within the window", () => {
  assert.deepEqual(occurrenceDates("2024-02-29", "yearly", "2026-02-28"), [
    "2024-02-29",
    "2025-02-28",
    "2026-02-28",
  ])
  assert.deepEqual(occurrenceDates("2026-12-01", "monthly", "2026-11-01"), [])
  assert.deepEqual(occurrenceDates("2026-10-01", null, "2026-12-01"), ["2026-10-01"])
})
