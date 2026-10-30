import { describe, it } from "node:test"
import assert from "node:assert/strict"
import { adjacentProfileTab, PROFILE_TAB_STRIP_ORDER } from "./profileTabStrip.ts"

describe("profileTabStrip", () => {
  it("follows ProfileTabs left-to-right order", () => {
    assert.deepEqual(PROFILE_TAB_STRIP_ORDER, [
      "trades",
      "reels",
      "posts",
      "calendar",
      "stats",
      "achievements",
    ])
  })

  it("swipe-left neighbors advance toward achievements", () => {
    assert.equal(adjacentProfileTab("trades", 1), "reels")
    assert.equal(adjacentProfileTab("stats", 1), "achievements")
    assert.equal(adjacentProfileTab("achievements", 1), null)
  })

  it("swipe-right neighbors move toward trades", () => {
    assert.equal(adjacentProfileTab("achievements", -1), "stats")
    assert.equal(adjacentProfileTab("reels", -1), "trades")
    assert.equal(adjacentProfileTab("trades", -1), null)
  })
})

export {}
