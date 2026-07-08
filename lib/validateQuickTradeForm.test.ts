import { describe, expect, it } from "vitest"
import { validateQuickTradeForm } from "./validateQuickTradeForm"

const validBase = {
  hasAccount: true,
  ticker: "ES",
  pnl: "450",
  points: "12.5",
  contracts: "2",
  rr: "",
  entryDate: "2026-07-01",
  exitDate: "2026-07-01",
  entryTime: "",
  exitTime: "",
  decimalError: null,
}

describe("validateQuickTradeForm", () => {
  it("returns the first missing required field in form order", () => {
    expect(validateQuickTradeForm({ ...validBase, hasAccount: false })).toEqual({
      ok: false,
      kind: "missing",
      field: "account",
      message: "Please select a Trading Account.",
    })

    expect(validateQuickTradeForm({ ...validBase, ticker: "" })).toEqual({
      ok: false,
      kind: "missing",
      field: "symbol",
      message: "Please enter a Symbol.",
    })

    expect(validateQuickTradeForm({ ...validBase, pnl: "" })).toEqual({
      ok: false,
      kind: "missing",
      field: "pnl",
      message: "Please enter P&L.",
    })
  })

  it("passes when required fields are present", () => {
    expect(validateQuickTradeForm(validBase)).toEqual({ ok: true })
  })
})
