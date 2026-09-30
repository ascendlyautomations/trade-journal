import { describe, it } from "node:test"
import { formatPublicAccountTypeLabel, publicAccountBadgeFromTrade, sanitizeTradeForViewer, PUBLIC_TRADE_SELECT, } from "./publicAccountPrivacy.ts"
import assert from "node:assert/strict"

describe("publicAccountPrivacy", () => {
  it("maps account types to public badge labels", () => {
    assert.equal(formatPublicAccountTypeLabel("eval"), "Evaluation")
    assert.equal(formatPublicAccountTypeLabel("live"), "Live")
    assert.equal(formatPublicAccountTypeLabel("funded"), "Funded")
    assert.equal(formatPublicAccountTypeLabel("backtest"), "Backtest")
    assert.equal(formatPublicAccountTypeLabel("personal"), "Personal")
  })

  it("derives badge from trade mode/type only", () => {
    assert.equal(
      publicAccountBadgeFromTrade({
        account_type: null,
        mode: "eval",
      }),
      "Evaluation"
    )
    assert.equal(
      publicAccountBadgeFromTrade({
        account_type: "funded",
        mode: "live",
      }),
      "Funded"
    )
  })

  it("strips identifiers for non-owners", () => {
    const trade = {
      id: "1",
      account_name: "Tradovate Live",
      account_number: "92813",
      account_id: "abc",
      account_size: "50K",
      account_type: "live",
    }
    const sanitized = sanitizeTradeForViewer(trade, { isOwner: false })
    assert.ok(sanitized)
    assert.equal(sanitized.account_name, undefined)
    assert.equal(sanitized.account_number, undefined)
    assert.equal(sanitized.account_id, undefined)
    assert.equal(sanitized.account_size, undefined)
    assert.equal(sanitized.account_type, "live")
  })

  it("does not strip fields for owner", () => {
    const trade = { account_name: "My Account", account_type: "live" }
    const sanitized = sanitizeTradeForViewer(trade, { isOwner: true })
    assert.ok(sanitized)
    assert.equal(sanitized.account_name, "My Account")
  })

  it("public select omits account identifiers", () => {
    const columns = PUBLIC_TRADE_SELECT.split(",").map((c) => c.trim())
    assert.ok(!columns.includes("account_name"))
    assert.ok(!columns.includes("account_id"))
    assert.ok(!columns.includes("account_size"))
    assert.ok(!columns.includes("post_to_feed"))
    assert.ok(columns.includes("account_type"))
  })

  it("public select omits owner journal fields", () => {
    assert.ok(!PUBLIC_TRADE_SELECT.includes("notes"))
    assert.ok(!PUBLIC_TRADE_SELECT.includes("psychology_notes"))
    assert.ok(!PUBLIC_TRADE_SELECT.includes("strategy"))
    assert.ok(!PUBLIC_TRADE_SELECT.includes("emotion"))
  })

  it("strips journal fields for non-owners", () => {
    const trade = {
      id: "1",
      notes: "secret",
      psychology_notes: "private",
      strategy: "breakout",
      account_type: "live",
    }
    const sanitized = sanitizeTradeForViewer(trade, { isOwner: false })
    assert.ok(sanitized)
    assert.equal(sanitized.notes, undefined)
    assert.equal(sanitized.psychology_notes, undefined)
    assert.equal(sanitized.strategy, undefined)
    assert.equal(sanitized.account_type, "live")
  })
})
export {}
