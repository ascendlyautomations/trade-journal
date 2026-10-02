import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  accountCanAddTrades,
  countTradeEntryEnabledAccounts,
  filterAccountsForDropdown,
  filterAccountsForTradeEntry,
  needsFreePlanAccountSlotSelection,
} from "./freePlanAccountSlots.ts"

describe("freePlanAccountSlots", () => {
  it("defaults missing can_add_trades to enabled for the create quota", () => {
    assert.equal(accountCanAddTrades({ id: "1" }), true)
    assert.equal(accountCanAddTrades({ id: "1", can_add_trades: true }), true)
    assert.equal(accountCanAddTrades({ id: "1", can_add_trades: false }), false)
  })

  it("does not prompt for read-only slot selection", () => {
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
      false
    )
    assert.equal(countTradeEntryEnabledAccounts(accounts), 4)
  })

  it("keeps an active account with historical can_add_trades false journalable", () => {
    const filtered = filterAccountsForTradeEntry([
      { id: "1", can_add_trades: true, is_active: true },
      { id: "2", can_add_trades: false, is_active: true },
      { id: "3", can_add_trades: true, is_active: false },
    ])
    assert.deepEqual(
      filtered.map((row) => row.id),
      ["1", "2"]
    )
  })

  it("hides dropdown-off accounts from pickers without blocking trade entry", () => {
    const rows = [
      {
        id: "on",
        can_add_trades: false,
        is_active: true,
        show_in_account_dropdowns: true,
      },
      {
        id: "off",
        can_add_trades: false,
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
