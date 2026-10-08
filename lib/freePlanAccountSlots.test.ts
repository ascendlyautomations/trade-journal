import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  accountCanAddTrades,
  countTotalTradingAccounts,
  countTradeEntryEnabledAccounts,
  filterAccountsForDropdown,
  filterAccountsForTradeEntry,
  needsFreePlanAccountSlotSelection,
} from "./freePlanAccountSlots.ts"

describe("freePlanAccountSlots", () => {
  it("defaults missing can_add_trades to enabled for trade entry", () => {
    assert.equal(accountCanAddTrades({ id: "1" }), true)
    assert.equal(accountCanAddTrades({ id: "1", can_add_trades: true }), true)
    assert.equal(accountCanAddTrades({ id: "1", can_add_trades: false }), false)
  })

  it("counts total accounts for creation quota", () => {
    const accounts = [
      { id: "1", can_add_trades: true },
      { id: "2", can_add_trades: false },
      { id: "3", can_add_trades: false },
    ]
    assert.equal(countTotalTradingAccounts(accounts), 3)
    assert.equal(countTradeEntryEnabledAccounts(accounts), 1)
  })

  it("prompts for slot selection when more than 3 entry-enabled accounts", () => {
    const accounts = [
      { id: "1", can_add_trades: true },
      { id: "2", can_add_trades: true },
      { id: "3", can_add_trades: true },
      { id: "4", can_add_trades: true },
      { id: "5", can_add_trades: false, is_active: true },
    ]
    assert.equal(
      needsFreePlanAccountSlotSelection({ is_pro: true }, accounts),
      false
    )
    assert.equal(
      needsFreePlanAccountSlotSelection(
        { is_pro: false, subscription_status: "inactive" },
        accounts
      ),
      true
    )
    assert.equal(countTradeEntryEnabledAccounts(accounts), 4)
  })

  it("filters inactive and read-only accounts from trade entry pickers", () => {
    const filtered = filterAccountsForTradeEntry([
      { id: "1", can_add_trades: true, is_active: true },
      { id: "2", can_add_trades: false, is_active: true },
      { id: "3", can_add_trades: true, is_active: false },
    ])
    assert.deepEqual(
      filtered.map((row) => row.id),
      ["1"]
    )
  })

  it("hides dropdown-off accounts from pickers without blocking trade entry", () => {
    const rows = [
      {
        id: "on",
        can_add_trades: true,
        is_active: true,
        show_in_account_dropdowns: true,
      },
      {
        id: "off",
        can_add_trades: true,
        is_active: true,
        show_in_account_dropdowns: false,
      },
    ]
    assert.deepEqual(
      filterAccountsForTradeEntry(rows).map((row) => row.id),
      ["on", "off"]
    )
    assert.deepEqual(
      filterAccountsForDropdown(rows).map((row) => row.id),
      ["on"]
    )
  })
})
