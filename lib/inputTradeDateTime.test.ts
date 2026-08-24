import { describe, it } from "node:test"
import { buildDateTime, dateTimeFieldsFromTrade, getTradeFormDuration, isExitBeforeEntry, toDateInputValue, toTimeInputValue, } from "./inputTradeDateTime.ts"
import assert from "node:assert/strict"

describe("inputTradeDateTime", () => {
  it("builds same-day entry and exit ISO", () => {
    const entry = buildDateTime("2024-06-08", "09:30")
    const exit = buildDateTime("2024-06-08", "15:45")
    assert.ok(entry)
    assert.ok(exit)
    const duration = getTradeFormDuration(entry, exit)
    assert.ok(duration)
    assert.match(duration, /\d+h/)
  })

  it("supports overnight entry (Jun 8 22:00 → Jun 9 02:00)", () => {
    const entry = buildDateTime("2024-06-08", "22:00")
    const exit = buildDateTime("2024-06-09", "02:00")
    assert.equal(
      isExitBeforeEntry("2024-06-08", "22:00", "2024-06-09", "02:00"),
      false
    )
    assert.ok(getTradeFormDuration(entry, exit))
  })

  it("supports multi-day swing (Jun 8 → Jun 11)", () => {
    const entry = buildDateTime("2024-06-08", "09:30")
    const exit = buildDateTime("2024-06-11", "14:15")
    assert.equal(
      isExitBeforeEntry("2024-06-08", "09:30", "2024-06-11", "14:15"),
      false
    )
    const duration = getTradeFormDuration(entry, exit)
    assert.ok(duration)
    assert.match(duration, /3d/)
  })

  it("rejects exit before entry across dates", () => {
    assert.equal(
      isExitBeforeEntry("2024-06-11", "14:00", "2024-06-08", "09:00"),
      true
    )
  })

  it("loads TradeZella-style swing from stored ISO timestamps", () => {
    const entryIso = new Date("2024-06-08T09:30:00").toISOString()
    const exitIso = new Date("2024-06-11T14:15:00").toISOString()
    const fields = dateTimeFieldsFromTrade({
      entry_time: entryIso,
      exit_time: exitIso,
      trade_date: null,
    })
    assert.equal(fields.entryDate, toDateInputValue(entryIso))
    assert.equal(fields.exitDate, toDateInputValue(exitIso))
    assert.equal(fields.entryTime, toTimeInputValue(entryIso))
    assert.equal(fields.exitTime, toTimeInputValue(exitIso))
    assert.notEqual(fields.entryDate, fields.exitDate)
  })

  it("does not use trade_date when entry_time exists", () => {
    const entryIso = new Date("2024-06-08T10:00:00").toISOString()
    const exitIso = new Date("2024-06-08T11:00:00").toISOString()
    const fields = dateTimeFieldsFromTrade({
      entry_time: entryIso,
      exit_time: exitIso,
      trade_date: "2024-05-01",
    })
    assert.equal(fields.entryDate, toDateInputValue(entryIso))
    assert.equal(fields.exitDate, toDateInputValue(exitIso))
  })

  it("round-trips edited swing timestamps", () => {
    const entryIso = new Date("2024-06-08T09:30:00").toISOString()
    const exitIso = new Date("2024-06-11T14:15:00").toISOString()
    const loaded = dateTimeFieldsFromTrade({
      entry_time: entryIso,
      exit_time: exitIso,
    })
    const savedEntry = buildDateTime(loaded.entryDate, loaded.entryTime)
    const savedExit = buildDateTime(loaded.exitDate, loaded.exitTime)
    assert.equal(savedEntry, entryIso)
    assert.equal(savedExit, exitIso)
  })
})
export {}
