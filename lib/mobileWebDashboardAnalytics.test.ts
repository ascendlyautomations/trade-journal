import assert from "node:assert/strict"
import { describe, it } from "node:test"

import {
  MOBILE_WEB_SESSION_ORDER,
  mobileWebSessionTitle,
} from "./mobileWebDashboardAnalytics.ts"

describe("mobileWebDashboardAnalytics", () => {
  it("orders NY sub-sessions before London and Asia", () => {
    assert.deepEqual([...MOBILE_WEB_SESSION_ORDER], [
      "NY AM",
      "NY Lunch",
      "NY PM",
      "London",
      "Asia",
    ])
    assert.equal(mobileWebSessionTitle("NY AM"), "New York AM")
    assert.equal(mobileWebSessionTitle("NY Lunch"), "New York Lunch")
  })
})
