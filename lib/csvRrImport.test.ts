import { describe, it } from "node:test"
import { CSV_RR_HEADER_ALIASES, parseCsvRrValue } from "./csvRrAliases.ts"
import { buildTradesFromParsedCsv, findCsvRrColumnHeader, normalizeHeaderKey, resolveCsvHeaderField, } from "./csvTradeParsers.ts"
import { buildCsvImportDiagnostics } from "./csvImportDiagnostics.ts"
import assert from "node:assert/strict"

const USER_ID = "test-user-id"

function flexRow(overrides = {}) {
  return {
    Date: "2026-01-15",
    Symbol: "NQ",
    Direction: "Long",
    PnL: "150",
    ...overrides,
  }
}

describe("csvRrImport", () => {
  it("recognizes common RR column aliases case-insensitively", () => {
    const samples = [
      "RR",
      "rr",
      "R:R",
      "Risk Reward",
      "risk reward",
      "Risk:Reward",
      "Risk/Reward",
      "risk_reward",
      "riskReward",
      "R Multiple",
      "R-Multiple",
      "R",
    ]
    for (const header of samples) {
      assert.equal(
        resolveCsvHeaderField(header),
        "rr",
        `expected "${header}" to map to rr`
      )
    }
  })

  it("includes user-listed aliases in the shared alias list", () => {
    const normalized = new Set(CSV_RR_HEADER_ALIASES.map((a) => normalizeHeaderKey(a)))
    assert.ok(normalized.has("rr"))
    assert.ok(normalized.has("r r"))
    assert.ok(normalized.has("risk reward"))
    assert.ok(normalized.has("r multiple"))
    assert.ok(normalized.has("r"))
  })

  it("parseCsvRrValue preserves numeric values exactly", () => {
    assert.equal(parseCsvRrValue("2.5"), 2.5)
    assert.equal(parseCsvRrValue("1.75"), 1.75)
    assert.equal(parseCsvRrValue("-1"), -1)
    assert.equal(parseCsvRrValue("0.8"), 0.8)
    assert.equal(parseCsvRrValue(""), null)
    assert.equal(parseCsvRrValue(null), null)
  })

  it("imports RR from flexible CSV when column is present", () => {
    const result = buildTradesFromParsedCsv(
      [flexRow({ RR: "2.5" })],
      USER_ID
    )
    assert.equal(result.summary.success, 1)
    assert.equal(result.parsedTrades[0]?.rr, 2.5)
  })

  it("imports RR from flexible CSV with alternate header names", () => {
    const cases = [
      ["Risk:Reward", "1.75"],
      ["risk_reward", "-1"],
      ["R Multiple", "0.8"],
      ["riskReward", "3"],
    ]
    for (const [header, value] of cases) {
      const result = buildTradesFromParsedCsv(
        [flexRow({ [header]: value })],
        USER_ID
      )
      assert.equal(result.summary.success, 1, `failed for header ${header}`)
      assert.equal(
        result.parsedTrades[0]?.rr,
        Number(value),
        `wrong RR for header ${header}`
      )
    }
  })

  it("leaves RR null when CSV has no RR column", () => {
    const result = buildTradesFromParsedCsv([flexRow()], USER_ID)
    assert.equal(result.summary.success, 1)
    assert.equal(result.parsedTrades[0]?.rr, null)
  })

  it("does not estimate RR from entry, exit, or PnL", () => {
    const result = buildTradesFromParsedCsv(
      [
        flexRow({
          "Entry Price": "100",
          "Exit Price": "110",
          PnL: "500",
          Quantity: "2",
        }),
      ],
      USER_ID
    )
    assert.equal(result.summary.success, 1)
    assert.equal(result.parsedTrades[0]?.rr, null)
  })

  it("findCsvRrColumnHeader returns the original header name", () => {
    const row = flexRow({ RR: "2" })
    assert.equal(findCsvRrColumnHeader(row), "RR")
  })

  it("diagnostics note when RR column is detected", () => {
    const row = flexRow({ RR: "2.5", "Broker Custom Field": "x" })
    const parseResult = buildTradesFromParsedCsv([row], USER_ID)
    const diagnostics = buildCsvImportDiagnostics([row], parseResult)
    assert.ok(diagnostics)
    assert.equal(
      diagnostics.rrImportNote,
      "✓ Risk:Reward column detected (RR)"
    )
  })

  it("diagnostics note when RR column is missing on partial import", () => {
    const rows = [flexRow({ Symbol: "" })]
    const parseResult = buildTradesFromParsedCsv(rows, USER_ID)
    const diagnostics = buildCsvImportDiagnostics(rows, parseResult)
    assert.ok(diagnostics)
    assert.equal(
      diagnostics.rrImportNote,
      "Risk:Reward not found — skipped."
    )
  })
})
export {}
