import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { getTraxProAppleProductIdSet } from "./traxProProductIds.ts"
import { isAppleSubscriptionActive } from "./appleSubscription.ts"

const future = new Date(Date.now() + 86_400_000).toISOString()
const past = new Date(Date.now() - 86_400_000).toISOString()

describe("isAppleSubscriptionActive", () => {
  it("accepts active unexpired subscription", () => {
    assert.equal(
      isAppleSubscriptionActive({
        status: "active",
        expires_at: future,
        revoked_at: null,
      }),
      true
    )
  })

  it("accepts grace period", () => {
    assert.equal(
      isAppleSubscriptionActive({
        status: "grace_period",
        expires_at: future,
        revoked_at: null,
      }),
      true
    )
  })

  it("rejects expired subscription", () => {
    assert.equal(
      isAppleSubscriptionActive({
        status: "expired",
        expires_at: past,
        revoked_at: null,
      }),
      false
    )
  })

  it("rejects revoked subscription", () => {
    assert.equal(
      isAppleSubscriptionActive({
        status: "active",
        expires_at: future,
        revoked_at: past,
      }),
      false
    )
  })
})

describe("verifyAppleSignedTransactionInfo", () => {
  it("rejects missing JWS without credentials", async () => {
    const { verifyAppleSignedTransactionInfo } = await import(
      "./appleSubscription.ts"
    )
    const result = await verifyAppleSignedTransactionInfo("")
    assert.equal(result.ok, false)
  })
})

describe("TraxPro product IDs", () => {
  it("matches expected production identifiers", () => {
    const ids = getTraxProAppleProductIdSet()
    assert.deepEqual([...ids].sort(), [
      "com.tradetraxs.traxpro.monthly",
      "com.tradetraxs.traxpro.sixmonth",
      "com.tradetraxs.traxpro.yearly",
    ])
  })
})

describe("verifyAppleSignedNotification", () => {
  it("rejects missing signedPayload without credentials", async () => {
    const { verifyAppleSignedNotification } = await import(
      "./appleSubscription.ts"
    )
    const result = await verifyAppleSignedNotification("")
    assert.equal(result.ok, false)
  })
})
