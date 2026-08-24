import { describe, it } from "node:test"
import { csvTradeHasFutureDate, csvTradesHaveFutureDate, getLocalTodayDateInputValue, isDateAfterToday, isStartedTradingDateInFuture, tradeFormHasFutureDate, } from "./tradeDateValidation.ts"
import assert from "node:assert/strict"

const fixedNow = new Date(2026, 5, 15, 12, 0, 0) // 2026-06-15 local

describe("tradeDateValidation", () => {
  it("treats today as valid", () => {
    assert.equal(isDateAfterToday("2026-06-15", fixedNow), false)
  })

  it("rejects tomorrow in local timezone", () => {
    assert.equal(isDateAfterToday("2026-06-16", fixedNow), true)
  })

  it("allows past dates", () => {
    assert.equal(isDateAfterToday("2026-06-14", fixedNow), false)
  })

  it("flags future entry or exit on trade form", () => {
    assert.equal(
      tradeFormHasFutureDate({
        entryDate: "2026-06-15",
        exitDate: "2026-06-16",
      }),
      true
    )
    assert.equal(
      tradeFormHasFutureDate({
        entryDate: "2026-06-08",
        exitDate: "2026-06-11",
      }),
      false
    )
  })

  it("flags CSV trades with future date fields", () => {
    assert.equal(
      csvTradeHasFutureDate({
        date: "2026-06-16",
        entry_time: null,
        exit_time: null,
      }),
      true
    )
    assert.equal(
      csvTradesHaveFutureDate([
        { date: "2026-06-10", entry_time: null, exit_time: null },
        {
          date: "2026-06-15",
          entry_time: new Date("2026-06-16T10:00:00").toISOString(),
          exit_time: null,
        },
      ]),
      true
    )
  })

  it("formats local today", () => {
    assert.equal(getLocalTodayDateInputValue(fixedNow), "2026-06-15")
  })

  it("allows empty started trading date", () => {
    assert.equal(isStartedTradingDateInFuture(""), false)
    assert.equal(isStartedTradingDateInFuture(null), false)
  })

  it("rejects future started trading date", () => {
    assert.equal(isStartedTradingDateInFuture("2026-06-16", fixedNow), true)
    assert.equal(isStartedTradingDateInFuture("2026-06-15", fixedNow), false)
  })
})
export {}
