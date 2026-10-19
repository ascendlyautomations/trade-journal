import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  ALREADY_PRO_CHECKOUT_MESSAGE,
  ENTITLEMENT_UNAVAILABLE_MESSAGE,
  billingProviderLabel,
  clientCheckoutBlockReason,
  decideStripeCheckout,
  knownTraxProActiveForPreflight,
  parseBillingEntitlementResponse,
  resolveBillingProvider,
  resolveClientProAccess,
  snapshotHasLiveAppleSubscription,
  type BillingEntitlementSnapshot,
} from "./billingEntitlement.ts"

function snapshot(
  overrides: Partial<BillingEntitlementSnapshot> &
    Pick<BillingEntitlementSnapshot, "traxProActive" | "source" | "plan">
): BillingEntitlementSnapshot {
  return {
    billingInterval: null,
    subscriptionStatus: null,
    trialEndsAt: null,
    currentPeriodEndsAt: null,
    cancelAtPeriodEnd: false,
    appleExpiresAt: null,
    appleProductId: null,
    accessExpiresAt: null,
    issuedAt: "2026-10-17T00:00:00.000Z",
    appleSubscriptionStatus: null,
    appleRevokedAt: null,
    ...overrides,
  }
}

describe("Web reads the shared entitlement snapshot", () => {
  it("recognizes an Apple subscriber as Pro", () => {
    const body = snapshot({
      traxProActive: true,
      source: "apple",
      plan: "pro",
      appleProductId: "com.tradetraxs.traxspro.monthly",
      appleSubscriptionStatus: "active",
    })
    const parsed = parseBillingEntitlementResponse(body)
    assert.equal(parsed?.traxProActive, true)
    assert.equal(
      resolveClientProAccess({
        signedIn: true,
        profileIsPro: false,
        status: "ready",
        traxProActive: parsed?.traxProActive ?? null,
      }),
      "pro"
    )
    assert.equal(resolveBillingProvider(parsed), "apple")
    assert.equal(billingProviderLabel("apple"), "App Store")
  })

  it("recognizes a Stripe subscriber when the snapshot source is manual", () => {
    const parsed = snapshot({
      traxProActive: true,
      source: "manual",
      plan: "pro",
      subscriptionStatus: "active",
      billingInterval: "monthly",
    })
    assert.equal(resolveBillingProvider(parsed), "stripe")
    assert.equal(
      resolveBillingProvider(
        snapshot({ traxProActive: true, source: "stripe", plan: "pro" })
      ),
      "stripe"
    )
    assert.equal(billingProviderLabel("stripe"), "Stripe")
    assert.equal(
      resolveClientProAccess({
        signedIn: true,
        profileIsPro: true,
        status: "ready",
        traxProActive: true,
      }),
      "pro"
    )
  })

  it("recognizes a live Stripe trial", () => {
    const parsed = snapshot({
      traxProActive: true,
      source: "manual",
      plan: "pro",
      subscriptionStatus: "trialing",
      trialEndsAt: "2026-10-31T00:00:00.000Z",
    })
    assert.equal(resolveBillingProvider(parsed), "stripe")
    assert.equal(
      decideStripeCheckout({ ok: true, traxProActive: true }).action,
      "block_pro"
    )
  })

  it("recognizes creator, early access, and launch access as included Pro", () => {
    for (const source of ["creator", "early_access", "launch_access", "manual"] as const) {
      const parsed = snapshot({
        traxProActive: true,
        source,
        plan: "pro",
        subscriptionStatus: source === "manual" ? null : "inactive",
      })
      assert.equal(resolveBillingProvider(parsed), "granted")
      assert.equal(billingProviderLabel("granted"), "Included with your account")
    }
  })

  it("recognizes a free user", () => {
    const parsed = snapshot({
      traxProActive: false,
      source: "none",
      plan: "free",
    })
    assert.equal(
      resolveClientProAccess({
        signedIn: true,
        profileIsPro: false,
        status: "ready",
        traxProActive: parsed.traxProActive,
      }),
      "free"
    )
    assert.equal(resolveBillingProvider(parsed), "unknown")
    assert.equal(billingProviderLabel("unknown"), null)
    assert.equal(decideStripeCheckout({ ok: true, traxProActive: false }).action, "proceed")
  })

  it("keeps access unknown when the entitlement request fails", () => {
    assert.equal(parseBillingEntitlementResponse(null), null)
    assert.equal(parseBillingEntitlementResponse({ plan: "pro" }), null)
    assert.equal(
      resolveClientProAccess({
        signedIn: true,
        profileIsPro: false,
        status: "error",
        traxProActive: null,
      }),
      "unknown"
    )
    assert.equal(knownTraxProActiveForPreflight("unknown"), null)
    assert.equal(decideStripeCheckout({ ok: false }).action, "unavailable")
    assert.equal(
      clientCheckoutBlockReason({
        signedIn: true,
        status: "error",
        traxProActive: null,
      }),
      ENTITLEMENT_UNAVAILABLE_MESSAGE
    )
  })

  it("blocks duplicate checkout when the snapshot confirms Pro", () => {
    assert.equal(
      clientCheckoutBlockReason({
        signedIn: true,
        status: "ready",
        traxProActive: true,
      }),
      ALREADY_PRO_CHECKOUT_MESSAGE
    )
    assert.equal(
      clientCheckoutBlockReason({
        signedIn: true,
        status: "loading",
        traxProActive: null,
      }),
      "Checking your plan. Try again in a moment."
    )
    assert.equal(
      clientCheckoutBlockReason({
        signedIn: true,
        status: "ready",
        traxProActive: false,
      }),
      null
    )
  })

  it("does not treat a live App Store subscription as Stripe billing", () => {
    const parsed = snapshot({
      traxProActive: true,
      source: "apple",
      plan: "pro",
      subscriptionStatus: "active",
      appleSubscriptionStatus: "active",
    })
    assert.equal(resolveBillingProvider(parsed), "apple")
    assert.equal(snapshotHasLiveAppleSubscription(parsed), true)
    assert.equal(
      snapshotHasLiveAppleSubscription({
        ...parsed,
        appleRevokedAt: "2026-10-01T00:00:00.000Z",
      }),
      false
    )
  })
})
