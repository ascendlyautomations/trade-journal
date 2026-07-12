const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const { matchesTradingAccountSearch } = require("./tradingAccountsSearch.ts")

const sampleAccount = {
  id: "uuid-1",
  name: "Alpha Futures",
  size: "50000",
  account_number: "12345678",
  mode: "eval",
  category: "Prop Firm",
  is_active: true,
  can_add_trades: true,
  note: "",
  rules: null,
}

describe("matchesTradingAccountSearch", () => {
  it("matches partial account display name case-insensitively", () => {
    assert.equal(matchesTradingAccountSearch(sampleAccount, "Alpha"), true)
    assert.equal(matchesTradingAccountSearch(sampleAccount, "futures"), true)
    assert.equal(matchesTradingAccountSearch(sampleAccount, "FUTURES"), true)
    assert.equal(matchesTradingAccountSearch(sampleAccount, "50k"), true)
  })

  it("matches partial Account ID case-insensitively", () => {
    assert.equal(matchesTradingAccountSearch(sampleAccount, "1234"), true)
    assert.equal(matchesTradingAccountSearch(sampleAccount, "5678"), true)
    assert.equal(matchesTradingAccountSearch(sampleAccount, "12345678"), true)
  })

  it("trims leading and trailing spaces in the query", () => {
    assert.equal(matchesTradingAccountSearch(sampleAccount, "  1234  "), true)
    assert.equal(matchesTradingAccountSearch(sampleAccount, "  alpha  "), true)
  })

  it("searches by name only when Account ID is missing", () => {
    const noId = { ...sampleAccount, account_number: null }
    assert.equal(matchesTradingAccountSearch(noId, "Alpha"), true)
    assert.equal(matchesTradingAccountSearch(noId, "1234"), false)
  })

  it("returns all accounts for an empty query", () => {
    assert.equal(matchesTradingAccountSearch(sampleAccount, ""), true)
    assert.equal(matchesTradingAccountSearch(sampleAccount, "   "), true)
  })
})
