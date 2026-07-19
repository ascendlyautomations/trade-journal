import assert from "node:assert/strict"
import test from "node:test"
import {
  deriveTradeModeFromAccount,
  resolveTradeModeBadgeLabel,
} from "./tradeMode.ts"

test("regular live account journals as live", () => {
  assert.equal(
    deriveTradeModeFromAccount({ mode: "Live", category: "Personal" }),
    "live"
  )
  assert.equal(
    deriveTradeModeFromAccount({ mode: "live", category: "Broker" }),
    "live"
  )
})

test("prop firm evaluation and funded accounts journal as live", () => {
  assert.equal(
    deriveTradeModeFromAccount({ mode: "Eval", category: "Prop Firm" }),
    "live"
  )
  assert.equal(
    deriveTradeModeFromAccount({ mode: "eval", category: "Prop Firm" }),
    "live"
  )
  assert.equal(
    deriveTradeModeFromAccount({ mode: "Funded", category: "Prop Firm" }),
    "live"
  )
  assert.equal(
    deriveTradeModeFromAccount({ mode: "funded", category: "Prop Firm" }),
    "live"
  )
})

test("sim accounts journal as sim", () => {
  assert.equal(
    deriveTradeModeFromAccount({ mode: "Sim", category: "Personal" }),
    "sim"
  )
  assert.equal(
    deriveTradeModeFromAccount({ mode: "sim", category: "Broker" }),
    "sim"
  )
})

test("backtest accounts journal as backtest", () => {
  assert.equal(
    deriveTradeModeFromAccount({ mode: "backtest", category: "Backtest" }),
    "backtest"
  )
  assert.equal(
    deriveTradeModeFromAccount({ mode: null, category: "Backtest" }),
    "backtest"
  )
})

test("missing account falls back to live", () => {
  assert.equal(deriveTradeModeFromAccount(null), "live")
  assert.equal(deriveTradeModeFromAccount({}), "live")
})

test("badge reflects account status over journal trade_mode", () => {
  assert.equal(
    resolveTradeModeBadgeLabel({ mode: "Funded", trade_mode: "live" }),
    "Funded"
  )
  assert.equal(
    resolveTradeModeBadgeLabel({ mode: "Eval", trade_mode: "live" }),
    "Evaluation"
  )
  assert.equal(
    resolveTradeModeBadgeLabel({ mode: "Live", trade_mode: "live" }),
    "Live"
  )
  assert.equal(
    resolveTradeModeBadgeLabel({ mode: "Sim", trade_mode: "sim" }),
    "SIM"
  )
})

test("badge uses legacy account_type when mode is missing", () => {
  assert.equal(
    resolveTradeModeBadgeLabel({ account_type: "funded", trade_mode: "live" }),
    "Funded"
  )
  assert.equal(
    resolveTradeModeBadgeLabel({ account_type: "eval" }),
    "Evaluation"
  )
})

test("badge falls back to linked account row, then trade_mode", () => {
  assert.equal(
    resolveTradeModeBadgeLabel({ trade_mode: "live" }, { mode: "Funded" }),
    "Funded"
  )
  assert.equal(resolveTradeModeBadgeLabel({ trade_mode: "backtest" }), "Backtest")
  assert.equal(resolveTradeModeBadgeLabel({}), null)
})

test("copy traded badge still wins", () => {
  assert.equal(
    resolveTradeModeBadgeLabel({
      mode: "Funded",
      trade_mode: "copy_traded",
      copied_account_ids: ["a", "b"],
    }),
    "Copy Traded ×2"
  )
})
