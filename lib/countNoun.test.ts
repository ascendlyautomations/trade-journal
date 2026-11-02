import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { countNoun } from "./countNoun.ts"

describe("countNoun", () => {
  it("keeps the noun on the same token as the count", () => {
    assert.equal(countNoun(1, "trader"), "1 trader")
    assert.equal(countNoun(2, "trader"), "2 traders")
    assert.equal(countNoun(1, "member"), "1 member")
    assert.equal(countNoun(12, "member"), "12 members")
  })
})
