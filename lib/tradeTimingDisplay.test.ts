const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  buildTradeTimingPresentation,
  formatHoldDurationFromTimes,
  formatHoldDurationSeconds,
  isMultiCalendarDayTrade,
} = require("./tradeTimingDisplay.ts")

describe("formatHoldDurationSeconds", () => {
  it("formats under 24 hours with hours and minutes", () => {
    assert.equal(formatHoldDurationSeconds(2 * 3600 + 15 * 60), "2h 15m")
    assert.equal(formatHoldDurationSeconds(45 * 60), "45m")
  })

  it("formats 24+ hours as days and hours only", () => {
    assert.equal(formatHoldDurationSeconds(26 * 3600), "1d 2h")
    assert.equal(formatHoldDurationSeconds(53 * 3600), "2d 5h")
    assert.equal(formatHoldDurationSeconds(168 * 3600), "7d 0h")
  })

  it("does not include minutes for multi-day durations", () => {
    const label = formatHoldDurationSeconds(26 * 3600 + 17 * 60)
    assert.equal(label, "1d 2h")
    assert.ok(!label.includes("m"))
  })
})

describe("isMultiCalendarDayTrade", () => {
  it("detects different calendar days", () => {
    const entry = new Date("2026-06-08T09:30:00").toISOString()
    const exit = new Date("2026-06-11T14:15:00").toISOString()
    assert.equal(isMultiCalendarDayTrade(entry, exit), true)
  })

  it("treats same calendar day as not multi-day", () => {
    const entry = new Date("2026-06-08T09:30:00").toISOString()
    const exit = new Date("2026-06-08T15:45:00").toISOString()
    assert.equal(isMultiCalendarDayTrade(entry, exit), false)
  })
})

describe("buildTradeTimingPresentation", () => {
  it("builds compact multi-day rows with prices and duration", () => {
    const entry = new Date("2026-06-02T10:15:00").toISOString()
    const exit = new Date("2026-06-08T09:30:00").toISOString()
    const view = buildTradeTimingPresentation({
      entry_time: entry,
      exit_time: exit,
      entry_price: 23456,
      exit_price: 23458,
    })

    assert.match(view.priceRow ?? "", /Entry Price: \$23,456\.00/)
    assert.match(view.priceRow ?? "", /Exit Price: \$23,458\.00/)
    assert.ok(view.priceRow?.includes("→"))
    assert.match(view.dateTimeRow ?? "", /6\/2\/26/)
    assert.match(view.dateTimeRow ?? "", /6\/8\/26/)
    assert.ok(view.dateTimeRow?.includes("→"))
    assert.match(view.dateTimeRow ?? "", /• \d+d \d+h/)
  })

  it("builds compact same-day rows with prices and duration", () => {
    const entry = new Date("2026-06-08T09:30:00").toISOString()
    const exit = new Date("2026-06-08T10:15:00").toISOString()
    const view = buildTradeTimingPresentation({
      entry_time: entry,
      exit_time: exit,
      entry_price: 23456,
      exit_price: 23458,
    })

    assert.ok(view.priceRow?.includes("→"))
    assert.match(view.dateTimeRow ?? "", /6\/8\/26/)
    assert.ok(view.dateTimeRow?.includes("→"))
    assert.match(view.dateTimeRow ?? "", /• 45m$/)
  })

  it("omits price row when prices are missing", () => {
    const entry = new Date("2026-06-08T09:30:00").toISOString()
    const exit = new Date("2026-06-08T10:15:00").toISOString()
    const view = buildTradeTimingPresentation({
      entry_time: entry,
      exit_time: exit,
    })

    assert.equal(view.priceRow, null)
    assert.match(view.dateTimeRow ?? "", /• 45m$/)
  })
})

describe("formatHoldDurationFromTimes", () => {
  it("matches seconds-based formatting for swing trades", () => {
    const entry = new Date("2026-06-08T09:30:00").toISOString()
    const exit = new Date("2026-06-11T14:15:00").toISOString()
    assert.match(formatHoldDurationFromTimes(entry, exit) ?? "", /3d/)
  })
})
