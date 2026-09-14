import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  resolveExternalAccountIdFromPropsEvent,
  tradovatePropsEventTriggersSync,
} from "./tradovateSyncEventRouting.ts"

describe("tradovate sync event routing", () => {
  it("fill/order/executionReport trigger sync", () => {
    assert.equal(tradovatePropsEventTriggersSync("fill"), true)
    assert.equal(tradovatePropsEventTriggersSync("order"), true)
    assert.equal(tradovatePropsEventTriggersSync("executionReport"), true)
    assert.equal(tradovatePropsEventTriggersSync("cashBalance"), false)
  })

  it("resolves account from order cache for fill", () => {
    const map = new Map([["99", "12345"]])
    const id = resolveExternalAccountIdFromPropsEvent(
      {
        entityType: "fill",
        eventType: "Created",
        entity: { orderId: 99 },
      },
      map
    )
    assert.equal(id, "12345")
  })
})
