import assert from "node:assert/strict"
import { describe, it } from "node:test"

import { analyticsCalendarDay } from "./analyticsCalendarDay.ts"
import { parseDateLike } from "../formatDate.ts"

describe("analytics timestamp parsing (mirrors SQL)", () => {
  it("parses Z suffix with fractional seconds", () => {
    const d = parseDateLike("2026-06-23T01:20:25.000Z")
    assert.ok(d)
    assert.equal(analyticsCalendarDay({ entryTime: "2026-06-23T01:20:25.000Z" }), "2026-06-22")
  })

  it("parses space-separated +00 short offset (production import format)", () => {
    const d = parseDateLike("2025-10-13 16:10:00+00")
    assert.ok(d)
    assert.equal(
      analyticsCalendarDay({ entryTime: "2025-10-13 16:10:00+00" }),
      "2025-10-13"
    )
  })

  it("parses +00:00 explicit offset", () => {
    assert.equal(
      analyticsCalendarDay({ entryTime: "2025-10-02 14:35:00+00:00" }),
      "2025-10-02"
    )
  })

  it("timezone-less strings treated as UTC", () => {
    assert.equal(
      analyticsCalendarDay({ entryTime: "2026-06-22 23:58:10.601163" }),
      "2026-06-22"
    )
  })

  it("Monday 19:30 ET stays Monday (normal calendar)", () => {
    assert.equal(
      analyticsCalendarDay({ entryTime: "2026-08-10T23:30:00Z" }),
      "2026-08-10"
    )
  })
})
