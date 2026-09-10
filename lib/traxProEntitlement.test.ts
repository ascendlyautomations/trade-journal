import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  buildTraxProEntitlementSnapshot,
  isTraxProActive,
  resolveTraxProEntitlementSource,
} from "./traxProEntitlement.ts"
import type { AppleSubscriptionRow } from "./appleSubscription.ts"

const future = new Date(Date.now() + 86_400_000).toISOString()
const past = new Date(Date.now() - 86_400_000).toISOString()

function appleRow(
  overrides: Partial<AppleSubscriptionRow> = {}
): AppleSubscriptionRow {
  return {
    id: "apple-1",
    user_id: "user-1",
    original_transaction_id: "orig-1",
    latest_transaction_id: "tx-1",
    product_id: "com.tradetraxs.traxpro.monthly",
    environment: "Sandbox",
    billing_interval: "monthly",
    status: "active",
    expires_at: future,
    revoked_at: null,
    purchased_at: past,
    last_verified_at: past,
    ...overrides,
  }
}

describe("isTraxProActive unified entitlement", () => {
  it("keeps Stripe active users Pro without Apple", () => {
    assert.equal(
      isTraxProActive({
        is_pro: false,
        subscription_status: "active",
      }),
      true
    )
  })

  it("keeps manual is_pro users Pro", () => {
    assert.equal(
      isTraxProActive({ is_pro: true, subscription_status: null }),
      true
    )
  })

  it("keeps creator access Pro", () => {
    assert.equal(
      isTraxProActive({
        is_pro: false,
        creator_access: true,
        subscription_status: null,
      }),
      true
    )
  })

  it("grants Pro from verified active Apple subscription", () => {
    assert.equal(
      isTraxProActive(
        { is_pro: false, subscription_status: null },
        appleRow()
      ),
      true
    )
  })

  it("rejects expired Apple subscription when profile is free", () => {
    assert.equal(
      isTraxProActive(
        { is_pro: false, subscription_status: null },
        appleRow({ status: "expired", expires_at: past })
      ),
      false
    )
  })

  it("rejects revoked Apple subscription", () => {
    assert.equal(
      isTraxProActive(
        { is_pro: false, subscription_status: null },
        appleRow({ status: "revoked", revoked_at: past })
      ),
      false
    )
  })

  it("Stripe + Apple together remain Pro", () => {
    const snapshot = buildTraxProEntitlementSnapshot(
      { is_pro: false, subscription_status: "active" },
      appleRow()
    )
    assert.equal(snapshot.traxProActive, true)
    assert.equal(resolveTraxProEntitlementSource(snapshot.profile, snapshot.appleSubscription), "stripe")
  })

  it("Apple-only user resolves apple source", () => {
    const snapshot = buildTraxProEntitlementSnapshot(
      { is_pro: false, subscription_status: null },
      appleRow()
    )
    assert.equal(snapshot.traxProActive, true)
    assert.equal(snapshot.source, "apple")
  })

  it("inactive free user remains free", () => {
    const snapshot = buildTraxProEntitlementSnapshot(
      { is_pro: false, subscription_status: null },
      null
    )
    assert.equal(snapshot.traxProActive, false)
    assert.equal(snapshot.source, "none")
  })
})
