import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  accountCanAddTrades,
  countTradeEntryEnabledAccounts,
  filterAccountsForTradeEntry,
  needsFreePlanAccountSlotSelection,
} from "./freePlanAccountSlots.ts"

describe("freePlanAccountSlots", () => {
  it("defaults missing can_add_trades to enabled", () => {
    assert.equal(accountCanAddTrades({ id: "1" }), true)
    assert.equal(accountCanAddTrades({ id: "1", can_add_trades: true }), true)
    assert.equal(accountCanAddTrades({ id: "1", can_add_trades: false }), false)
  })

  it("does not require selection for Pro or <=3 entry-enabled accounts", () => {
    const accounts = [
      { id: "1", can_add_trades: true },
      { id: "2", can_add_trades: true },
      { id: "3", can_add_trades: true },
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
  })

  it("requires selection when Free and more than 3 entry-enabled", () => {
    const accounts = [
      { id: "1", can_add_trades: true },
      { id: "2", can_add_trades: true },
      { id: "3", can_add_trades: true },
      { id: "4", can_add_trades: true },
    ]
    assert.equal(
      needsFreePlanAccountSlotSelection(
        { is_pro: false, subscription_status: "inactive" },
        accounts
      ),
      true
    )
    assert.equal(countTradeEntryEnabledAccounts(accounts), 4)
  })

  it("trade-entry filter keeps only entry-enabled and soft-active accounts", () => {
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
})
