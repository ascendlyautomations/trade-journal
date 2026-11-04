import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  accountCanAddTrades,
  countTotalTradingAccounts,
  countTradeEntryEnabledAccounts,
  filterAccountsForDropdown,
  filterAccountsForTradeEntry,
  freePlanSlotSelectionRequired,
  needsFreePlanAccountSlotSelection,
  persistedTradeEntrySelectionIds,
} from "./freePlanAccountSlots.ts"

describe("freePlanAccountSlots", () => {
  it("requires explicit can_add_trades true for trade entry", () => {
    assert.equal(accountCanAddTrades({ id: "1" }), false)
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

  it("does not treat a missing entitlement as Free", () => {
    const accounts = [
      { id: "1", can_add_trades: true },
      { id: "2", can_add_trades: true },
      { id: "3", can_add_trades: true },
      { id: "4", can_add_trades: true },
    ]
    const staleEpoch = { required: 2, confirmed: 1 }
    assert.equal(freePlanSlotSelectionRequired(null, accounts), false)
    assert.equal(freePlanSlotSelectionRequired(true, accounts), false)
    assert.equal(freePlanSlotSelectionRequired(false, accounts, staleEpoch), true)
    const settled = [
      { id: "1", can_add_trades: true },
      { id: "2", can_add_trades: true },
      { id: "3", can_add_trades: true },
      { id: "4", can_add_trades: false },
    ]
    assert.equal(
      freePlanSlotSelectionRequired(false, settled, { required: 1, confirmed: 1 }),
      false
    )
  })

  it("restores a saved 1–3 selection and ignores an unchosen set", () => {
    assert.deepEqual(
      persistedTradeEntrySelectionIds([
        { id: "a", can_add_trades: true },
        { id: "b", can_add_trades: false },
        { id: "c", can_add_trades: true },
      ]),
      ["a", "c"]
    )
    assert.deepEqual(
      persistedTradeEntrySelectionIds([
        { id: "1", can_add_trades: true },
        { id: "2", can_add_trades: true },
        { id: "3", can_add_trades: true },
        { id: "4", can_add_trades: true },
      ]),
      []
    )
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

  it("hides filter-hidden accounts from trade entry pickers", () => {
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
      ["on"]
    )
    assert.deepEqual(
      filterAccountsForDropdown(rows).map((row) => row.id),
      ["on"]
    )
  })
})
