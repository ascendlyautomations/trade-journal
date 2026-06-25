const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  buildTradeAccountFilterKey,
  formatAccountBalanceForDisplay,
  formatAccountLabelForDisplay,
  formatAccountNameWithSizeDisplay,
  formatTradeAccountDisplay,
  formatTradeAccountNameSizeLine,
  resolveTradeAccountName,
  tradeMatchesAccountFilter,
} = require("./tradeAccountDisplay.ts")

describe("formatAccountBalanceForDisplay", () => {
  it("abbreviates thousands", () => {
    assert.equal(formatAccountBalanceForDisplay(50000), "50k")
    assert.equal(formatAccountBalanceForDisplay("100000"), "100k")
    assert.equal(formatAccountBalanceForDisplay("150000"), "150k")
    assert.equal(formatAccountBalanceForDisplay("25000"), "25k")
    assert.equal(formatAccountBalanceForDisplay("300000"), "300k")
    assert.equal(formatAccountBalanceForDisplay("50K"), "50k")
  })

  it("leaves non-numeric unchanged", () => {
    assert.equal(
      formatAccountBalanceForDisplay("Personal Account"),
      "Personal Account"
    )
    assert.equal(formatAccountBalanceForDisplay("999"), "999")
  })
})

describe("formatAccountLabelForDisplay", () => {
  it("abbreviates trailing balance", () => {
    assert.equal(formatAccountLabelForDisplay("My Sim 25000"), "My Sim 25k")
    assert.equal(
      formatAccountLabelForDisplay("Personal Account"),
      "Personal Account"
    )
  })
})

describe("formatAccountNameWithSizeDisplay", () => {
  it("combines name and size with k abbreviation", () => {
    assert.equal(
      formatAccountNameWithSizeDisplay("Tradovate", "50000"),
      "Tradovate 50k"
    )
    assert.equal(
      formatAccountNameWithSizeDisplay("My Sim 25000", null),
      "My Sim 25k"
    )
  })
})

describe("resolveTradeAccountName", () => {
  it("prefers linked account row", () => {
    assert.equal(
      resolveTradeAccountName(
        { account_name: "Stale Name", account_id: "acc-1" },
        { name: "Live Account" }
      ),
      "Live Account"
    )
  })

  it("falls back to trade field", () => {
    assert.equal(
      resolveTradeAccountName({ account_name: "Cached Name" }, null),
      "Cached Name"
    )
  })
})

describe("buildTradeAccountFilterKey", () => {
  it("uses resolved name and raw size for filters", () => {
    assert.equal(
      buildTradeAccountFilterKey(
        {
          account_name: "Old",
          account_size: "50000",
          account_id: "uuid-1",
        },
        { name: "Renamed", account_size: "50000" }
      ),
      "Renamed|50000|uuid-1"
    )
  })
})

describe("tradeMatchesAccountFilter", () => {
  it("matches renamed account key", () => {
    const trade = {
      account_name: "Old",
      account_size: "50000",
      account_id: "uuid-1",
    }
    const accountRow = { name: "Renamed", account_size: "50000" }
    assert.equal(
      tradeMatchesAccountFilter(trade, "Renamed|50000|uuid-1", accountRow),
      true
    )
    assert.equal(
      tradeMatchesAccountFilter(trade, "Old|50000|uuid-1", accountRow),
      false
    )
  })
})

describe("formatTradeAccountDisplay", () => {
  it("uses linked account name and abbreviated size", () => {
    assert.equal(
      formatTradeAccountDisplay(
        { account_name: "Old", account_size: "50K", mode: "funded" },
        { name: "Apex", account_size: "50000", account_number: "12345" }
      ),
      "Apex 50k Funded #12345"
    )
  })
})

describe("formatTradeAccountNameSizeLine", () => {
  it("uses linked account fields", () => {
    assert.equal(
      formatTradeAccountNameSizeLine(
        { account_name: "Old", account_size: "50K" },
        { name: "Apex", account_size: "50000" }
      ),
      "Apex 50k"
    )
  })
})
