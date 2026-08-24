import { describe, it } from "node:test"
import { buildAccountFilterKeyFromRow, buildAccountFilterOptionsFromRows, buildTradeAccountFilterKey, formatAccountBalanceForDisplay, formatAccountLabelForDisplay, formatAccountNameWithSizeDisplay, formatTradeAccountDisplay, formatTradeAccountNameSizeLine, formatTradingAccountSelectorLabel, resolveTradeAccountName, tradeMatchesAccountFilter, } from "./tradeAccountDisplay.ts"
import assert from "node:assert/strict"

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

describe("buildAccountFilterKeyFromRow", () => {
  it("uses account row fields", () => {
    assert.equal(
      buildAccountFilterKeyFromRow({
        id: "uuid-1",
        name: "Main",
        account_size: "50000",
      }),
      "Main|50000|uuid-1"
    )
  })
})

describe("buildAccountFilterOptionsFromRows", () => {
  it("includes active accounts with zero trades", () => {
    const options = buildAccountFilterOptionsFromRows([
      {
        id: "a1",
        name: "Empty Sim",
        account_size: "25000",
        mode: "sim",
        is_active: true,
      },
      {
        id: "a2",
        name: "Archived",
        account_size: "50000",
        is_active: false,
      },
    ])
    assert.equal(options.length, 2)
    assert.equal(options[0].value, "Empty Sim|25000|a1")
    assert.equal(options[0].label, "Empty Sim 25k • Sim")
    assert.equal(options[0].accountType, "sim")
    assert.equal(options[1].value, "Archived|50000|a2")
    assert.equal(options[1].label, "Archived 50k • Live")
  })

  it("marks read-only accounts in historical filter labels", () => {
    const options = buildAccountFilterOptionsFromRows([
      {
        id: "a1",
        name: "Legacy",
        account_size: "50000",
        mode: "live",
        is_active: true,
        can_add_trades: false,
      },
    ])
    assert.equal(options[0].label, "Legacy 50k • Live (Read Only)")
    assert.equal(options[0].readOnly, true)
  })

  it("includes account number before mode in label when present", () => {
    const options = buildAccountFilterOptionsFromRows([
      {
        id: "a1",
        name: "Apex",
        account_size: "50000",
        account_number: "104582",
        mode: "eval",
        is_active: true,
      },
    ])
    assert.equal(options[0].label, "Apex 50k • #104582 • Eval")
    assert.equal(options[0].labelName, "Apex 50k")
    assert.equal(options[0].labelSuffix, " • #104582 • Eval")
  })

  it("matches trade filter keys for linked trades", () => {
    const row = {
      id: "uuid-1",
      name: "Renamed",
      account_size: "50000",
      is_active: true,
    }
    const tradeKey = buildTradeAccountFilterKey(
      {
        account_name: "Old",
        account_size: "50000",
        account_id: "uuid-1",
      },
      row
    )
    const rowKey = buildAccountFilterKeyFromRow(row)
    assert.equal(tradeKey, rowKey)
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

describe("formatTradingAccountSelectorLabel", () => {
  it("orders name, account id, then mode", () => {
    assert.equal(
      formatTradingAccountSelectorLabel({
        name: "Apex",
        account_size: "50000",
        account_number: "104582",
        mode: "eval",
      }),
      "Apex 50k • #104582 • Eval"
    )
    assert.equal(
      formatTradingAccountSelectorLabel({
        name: "Personal Account",
        account_number: "99123",
        mode: "live",
      }),
      "Personal Account • #99123 • Live"
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
export {}
