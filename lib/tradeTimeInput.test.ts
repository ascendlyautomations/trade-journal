import { describe, it } from "node:test"
import { formatHhmmForDisplay, hhmmToParts, normalizeTradeTimeValue, parseTypedTradeTime, partsToHhmm, } from "./tradeTimeInput.ts"
import assert from "node:assert/strict"

describe("tradeTimeInput", () => {
  it("round-trips HH:mm through 12h parts", () => {
    assert.deepEqual(hhmmToParts("00:00"), {
      hour12: 12,
      minute: 0,
      period: "AM",
    })
    assert.deepEqual(hhmmToParts("09:30"), {
      hour12: 9,
      minute: 30,
      period: "AM",
    })
    assert.deepEqual(hhmmToParts("12:05"), {
      hour12: 12,
      minute: 5,
      period: "PM",
    })
    assert.deepEqual(hhmmToParts("21:15"), {
      hour12: 9,
      minute: 15,
      period: "PM",
    })
    assert.equal(partsToHhmm(9, 30, "AM"), "09:30")
    assert.equal(partsToHhmm(12, 0, "AM"), "00:00")
    assert.equal(partsToHhmm(12, 5, "PM"), "12:05")
    assert.equal(partsToHhmm(9, 15, "PM"), "21:15")
  })

  it("formats display with AM/PM", () => {
    assert.equal(formatHhmmForDisplay("09:30"), "9:30 AM")
    assert.equal(formatHhmmForDisplay("21:05"), "9:05 PM")
    assert.equal(formatHhmmForDisplay(""), "")
  })

  it("parses typed 12h and 24h strings", () => {
    assert.equal(parseTypedTradeTime("9:30 AM"), "09:30")
    assert.equal(parseTypedTradeTime("9:30pm"), "21:30")
    assert.equal(parseTypedTradeTime("21:05"), "21:05")
    assert.equal(parseTypedTradeTime("930am"), "09:30")
    assert.equal(parseTypedTradeTime(""), "")
    assert.equal(parseTypedTradeTime("nope"), null)
  })

  it("normalizes stored values", () => {
    assert.equal(normalizeTradeTimeValue("9:30 AM"), "09:30")
    assert.equal(normalizeTradeTimeValue("09:30:00"), "09:30")
    assert.equal(normalizeTradeTimeValue("09:30"), "09:30")
  })
})
export {}
