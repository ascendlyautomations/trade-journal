import assert from "node:assert/strict"
import { describe, it } from "node:test"

import {
  analyticsCalendarDay,
  analyticsLegacyTradingDayKey,
  analyticsRealizedSortMs,
} from "./analyticsCalendarDay.ts"

describe("analyticsCalendarDay (normal ET civil date)", () => {
  it("Monday 10:00 AM ET → Monday", () => {
    // 2026-08-10 14:00:00Z = 10:00 ET (EDT)
    const key = analyticsCalendarDay({
      entryTime: "2026-08-10T14:00:00Z",
    })
    assert.equal(key, "2026-08-10")
  })

  it("Monday 7:30 PM ET → Monday (no 18:00 rollover)", () => {
    // 2026-08-10 23:30:00Z = 19:30 ET
    const key = analyticsCalendarDay({
      entryTime: "2026-08-10T23:30:00Z",
    })
    assert.equal(key, "2026-08-10")
  })

  it("legacy trading day rolls Monday 7:30 PM ET to Tuesday", () => {
    const legacy = analyticsLegacyTradingDayKey({
      entryTime: "2026-08-10T23:30:00Z",
    })
    assert.equal(legacy, "2026-08-11")
    const normal = analyticsCalendarDay({
      entryTime: "2026-08-10T23:30:00Z",
    })
    assert.equal(normal, "2026-08-10")
  })

  it("prefers entry_time over exit_time for calendar day", () => {
    const key = analyticsCalendarDay({
      entryTime: "2026-08-10T14:00:00Z",
      exitTime: "2026-08-11T14:00:00Z",
    })
    assert.equal(key, "2026-08-10")
  })

  it("falls back to exit_time then created_at", () => {
    assert.equal(
      analyticsCalendarDay({ exitTime: "2026-08-12T14:00:00Z" }),
      "2026-08-12"
    )
    assert.equal(
      analyticsCalendarDay({ createdAt: "2026-08-13T14:00:00Z" }),
      "2026-08-13"
    )
  })

  it("returns null when no timestamps", () => {
    assert.equal(analyticsCalendarDay({}), null)
  })

  it("realized sort prefers exit over entry", () => {
    const exitMs = analyticsRealizedSortMs({
      entryTime: "2026-08-10T14:00:00Z",
      exitTime: "2026-08-10T20:00:00Z",
    })
    assert.equal(exitMs, Date.parse("2026-08-10T20:00:00Z"))
  })
})
