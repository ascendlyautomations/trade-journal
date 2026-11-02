import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { buildDemoWithdrawalsHistory } from "./demoWithdrawalsHistory.ts"

describe("buildDemoWithdrawalsHistory", () => {
  it("returns funded prop payouts without querying supabase", () => {
    const history = buildDemoWithdrawalsHistory()
    assert.ok(history.accounts.length > 0)
    assert.equal(
      history.items.some(
        (item) => item.source === "fundedCycle" && item.amount === 2400
      ),
      true
    )
  })
})
