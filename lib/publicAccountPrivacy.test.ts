const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  formatPublicAccountTypeLabel,
  publicAccountBadgeFromTrade,
  sanitizeTradeForViewer,
  PUBLIC_TRADE_SELECT,
} = require("./publicAccountPrivacy.ts")

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
        account_name: "Apex 50K",
        account_type: "funded",
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
    assert.equal(sanitized.account_name, undefined)
    assert.equal(sanitized.account_number, undefined)
    assert.equal(sanitized.account_id, undefined)
    assert.equal(sanitized.account_size, undefined)
    assert.equal(sanitized.account_type, "live")
  })

  it("does not strip fields for owner", () => {
    const trade = { account_name: "My Account", account_type: "live" }
    const sanitized = sanitizeTradeForViewer(trade, { isOwner: true })
    assert.equal(sanitized.account_name, "My Account")
  })

  it("public select omits account identifiers", () => {
    assert.ok(!PUBLIC_TRADE_SELECT.includes("account_name"))
    assert.ok(!PUBLIC_TRADE_SELECT.includes("account_id"))
    assert.ok(!PUBLIC_TRADE_SELECT.includes("account_size"))
    assert.ok(!PUBLIC_TRADE_SELECT.includes("post_to_feed"))
    assert.ok(PUBLIC_TRADE_SELECT.includes("account_type"))
  })
})
