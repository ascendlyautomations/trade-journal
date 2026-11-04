import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  accountRowIsViewOnly,
  accountRowVisibleInAnalyticsFilters,
} from "./tradeAccountVisibility.ts"

describe("tradeAccountVisibility", () => {
  it("treats show_in_account_dropdowns false as hidden from filters", () => {
    assert.equal(
      accountRowVisibleInAnalyticsFilters({ show_in_account_dropdowns: false }),
      false
    )
    assert.equal(
      accountRowVisibleInAnalyticsFilters({ show_in_account_dropdowns: true }),
      true
    )
    assert.equal(accountRowVisibleInAnalyticsFilters({}), true)
  })

  it("view-only requires explicit can_add_trades false", () => {
    assert.equal(accountRowIsViewOnly({ can_add_trades: false }), true)
    assert.equal(accountRowIsViewOnly({ can_add_trades: true }), false)
    assert.equal(accountRowIsViewOnly({}), false)
  })
})
