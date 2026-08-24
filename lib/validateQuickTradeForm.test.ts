;(function () {
  const assert = require("node:assert/strict")
  const { describe, it } = require("node:test")
  const { validateQuickTradeForm } = require("./validateQuickTradeForm.ts")

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
      assert.deepEqual(validateQuickTradeForm({ ...validBase, hasAccount: false }), {
        ok: false,
        kind: "missing",
        field: "account",
        message: "Please select a Trading Account.",
      })

      assert.deepEqual(validateQuickTradeForm({ ...validBase, ticker: "" }), {
        ok: false,
        kind: "missing",
        field: "symbol",
        message: "Please enter a Symbol.",
      })

      assert.deepEqual(validateQuickTradeForm({ ...validBase, pnl: "" }), {
        ok: false,
        kind: "missing",
        field: "pnl",
        message: "Please enter P&L.",
      })
    })

    it("passes when required fields are present", () => {
      assert.deepEqual(validateQuickTradeForm(validBase), { ok: true })
    })
  })
})()
