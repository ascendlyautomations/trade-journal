import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { tradeVisibleInCalendarFilters } from "./calendarTradeVisibility.ts"
import { buildAccountFilterKeyFromRow } from "./tradeAccountDisplay.ts"

describe("tradeVisibleInCalendarFilters", () => {
  it("keeps the selected account after a save instead of showing every account", () => {
    const accountA = { id: "acct-a", name: "Eval", account_size: "50k" }
    const trades = [
      { account_id: "acct-a", mode: "live" },
      { account_id: "acct-b", mode: "live" },
    ]
    const visible = trades.filter((trade) =>
      tradeVisibleInCalendarFilters(trade, {
        accountFilter: buildAccountFilterKeyFromRow(accountA),
        accountRow: trade.account_id === "acct-a" ? accountA : null,
        selectedMode: "all",
      })
    )
    assert.deepEqual(
      visible.map((trade) => trade.account_id),
      ["acct-a"]
    )
  })

  it("still applies the mode filter with the account filter", () => {
    const accountA = { id: "acct-a", name: "Eval", account_size: "50k" }
    const trade = { account_id: "acct-a", mode: "paper", account_type: "sim" }
    assert.equal(
      tradeVisibleInCalendarFilters(trade, {
        accountFilter: buildAccountFilterKeyFromRow(accountA),
        accountRow: accountA,
        selectedMode: "live",
      }),
      false
    )
  })
})