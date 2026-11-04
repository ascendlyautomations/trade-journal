import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { copyTradingLinkedAccountIdSet } from "./copyTradingAccountIds.ts"

describe("copyTradingLinkedAccountIdSet", () => {
  it("collects unique account ids across groups", () => {
    const set = copyTradingLinkedAccountIdSet([
      { accountIds: ["a1", "a2"] },
      { accountIds: ["a2", "a3"] },
    ])
    assert.deepEqual([...set].sort(), ["a1", "a2", "a3"])
  })
})
