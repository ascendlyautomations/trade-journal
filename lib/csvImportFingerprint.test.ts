import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { csvTradeImportFingerprint } from "./csvImportFingerprint.ts"

describe("csvTradeImportFingerprint", () => {
  it("is stable for the same trade fields", () => {
    const trade = {
      account_id: "a1",
      ticker: "ES",
      direction: "long",
      entry_time: "2026-01-01T10:00:00Z",
      exit_time: "2026-01-01T10:05:00Z",
      pnl: 120.5,
      contracts: 2,
      entry_price: 5000,
      exit_price: 5001,
    }
    const a = csvTradeImportFingerprint(trade)
    const b = csvTradeImportFingerprint({ ...trade })
    assert.equal(a, b)
    assert.match(a, /^v1:[a-f0-9]{64}$/)
  })

  it("changes when a material field changes", () => {
    const base = {
      account_id: "a1",
      ticker: "NQ",
      direction: "short",
      entry_time: "2026-01-02T10:00:00Z",
      exit_time: "2026-01-02T10:10:00Z",
      pnl: -50,
      contracts: 1,
      entry_price: 18000,
      exit_price: 18010,
    }
    const left = csvTradeImportFingerprint(base)
    const right = csvTradeImportFingerprint({ ...base, pnl: -51 })
    assert.notEqual(left, right)
  })
})
