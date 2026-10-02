import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { X509Certificate } from "crypto"
import {
  appleAppAccountTokenMatchesUser,
  launchAccessGrantApplies,
  resolveEffectiveMonetizationFlags,
  shouldOfferStripeCheckout,
  type MonetizationGlobalSettings,
} from "./monetizationConfig.ts"
import { loadAppleRootCertificates } from "./appleRootCertificates.ts"
import {
  buildTraxProEntitlementSnapshot,
  resolveEntitlementAccessExpiresAt,
} from "./traxProEntitlement.ts"
import type { AppleSubscriptionRow } from "./appleSubscription.ts"

const future = new Date(Date.now() + 86_400_000).toISOString()
const past = new Date(Date.now() - 86_400_000).toISOString()

const flagsOff: MonetizationGlobalSettings = {
  iosPaywallEnabled: false,
  webPaywallEnabled: false,
  entitlementEnforcementEnabled: false,
  launchAccessMode: "none",
  launchAccessCutoffAt: null,
}

function appleRow(
  overrides: Partial<AppleSubscriptionRow> = {}
): AppleSubscriptionRow {
  return {
    id: "apple-1",
    user_id: "user-1",
    original_transaction_id: "orig-1",
    latest_transaction_id: "tx-1",
    product_id: "com.tradetraxs.traxspro.monthly",
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

describe("remote monetization flags", () => {
  it("defaults both flags false when config is missing", () => {
    assert.deepEqual(resolveEffectiveMonetizationFlags(null, null), {
      iosPaywallEnabled: false,
      webPaywallEnabled: false,
      entitlementEnforcementEnabled: false,
    })
  })

  it("keeps production flags false", () => {
    assert.deepEqual(resolveEffectiveMonetizationFlags(flagsOff, null), {
      iosPaywallEnabled: false,
      webPaywallEnabled: false,
      entitlementEnforcementEnabled: false,
    })
  })

  it("allows paywall without enforcement", () => {
    assert.deepEqual(
      resolveEffectiveMonetizationFlags(
        { ...flagsOff, iosPaywallEnabled: true },
        null
      ),
      {
        iosPaywallEnabled: true,
        webPaywallEnabled: false,
        entitlementEnforcementEnabled: false,
      }
    )
  })

  it("allows both flags on", () => {
    assert.deepEqual(
      resolveEffectiveMonetizationFlags(
        {
          ...flagsOff,
          iosPaywallEnabled: true,
          webPaywallEnabled: true,
          entitlementEnforcementEnabled: true,
        },
        null
      ),
      {
        iosPaywallEnabled: true,
        webPaywallEnabled: true,
        entitlementEnforcementEnabled: true,
      }
    )
  })

  it("lets a review account override only the paywall", () => {
    assert.deepEqual(
      resolveEffectiveMonetizationFlags(flagsOff, {
        iosPaywallEnabled: true,
        webPaywallEnabled: null,
        entitlementEnforcementEnabled: null,
      }),
      {
        iosPaywallEnabled: true,
        webPaywallEnabled: false,
        entitlementEnforcementEnabled: false,
      }
    )
  })
})

describe("launch access policy", () => {
  it("grants nobody while the policy is none", () => {
    assert.equal(
      launchAccessGrantApplies(past, {
        launchAccessMode: "none",
        launchAccessCutoffAt: future,
      }),
      false
    )
  })

  it("grants profiles created before an explicit cutoff", () => {
    assert.equal(
      launchAccessGrantApplies("2026-01-01T00:00:00.000Z", {
        launchAccessMode: "created_before_cutoff",
        launchAccessCutoffAt: "2026-06-01T00:00:00.000Z",
      }),
      true
    )
    assert.equal(
      launchAccessGrantApplies("2026-07-01T00:00:00.000Z", {
        launchAccessMode: "created_before_cutoff",
        launchAccessCutoffAt: "2026-06-01T00:00:00.000Z",
      }),
      false
    )
  })
})

describe("entitlement snapshot", () => {
  it("keeps a free profile free when launch access is off", () => {
    const snapshot = buildTraxProEntitlementSnapshot(
      { is_pro: false, subscription_status: null },
      null,
      {
        launchAccess: { launchAccessMode: "none", launchAccessCutoffAt: null },
        profileCreatedAt: past,
      }
    )
    assert.equal(snapshot.traxProActive, false)
    assert.equal(snapshot.source, "none")
  })

  it("recognizes Apple, Stripe, manual, creator, and early access", () => {
    assert.equal(
      buildTraxProEntitlementSnapshot(
        { is_pro: false, subscription_status: null },
        appleRow()
      ).source,
      "apple"
    )
    assert.equal(
      buildTraxProEntitlementSnapshot(
        { is_pro: false, subscription_status: "active", current_period_end: future },
        null
      ).source,
      "stripe"
    )
    assert.equal(
      buildTraxProEntitlementSnapshot({ is_pro: true, subscription_status: null }, null)
        .source,
      "manual"
    )
    assert.equal(
      buildTraxProEntitlementSnapshot(
        { is_pro: false, creator_access: true, subscription_status: null },
        null
      ).source,
      "creator"
    )
    const early = buildTraxProEntitlementSnapshot(
      {
        is_pro: false,
        subscription_status: null,
        early_access_status: "active",
        early_access_campaign_id: "traxs_pro_for_life_v1",
        early_access_enrollment_source: "standard_email",
        early_access_enrolled_at: past,
        early_access_started_at: past,
        early_access_ends_at: future,
      },
      null
    )
    assert.equal(early.source, "early_access")
    assert.equal(early.accessExpiresAt, future)
  })

  it("treats billing retry as active Apple access and revocation as inactive", () => {
    assert.equal(
      buildTraxProEntitlementSnapshot(
        { is_pro: false, subscription_status: null },
        appleRow({ status: "billing_retry" })
      ).traxProActive,
      true
    )
    assert.equal(
      buildTraxProEntitlementSnapshot(
        { is_pro: false, subscription_status: null },
        appleRow({ status: "grace_period" })
      ).traxProActive,
      true
    )
    const revoked = buildTraxProEntitlementSnapshot(
      { is_pro: false, subscription_status: null },
      appleRow({ status: "revoked", revoked_at: past, expires_at: past })
    )
    assert.equal(revoked.traxProActive, false)
  })

  it("expires Apple access at the Apple expiry", () => {
    assert.equal(
      resolveEntitlementAccessExpiresAt({
        source: "apple",
        traxProActive: true,
        trialEndsAt: null,
        currentPeriodEndsAt: null,
        appleExpiresAt: future,
      }),
      future
    )
  })

  it("can mark a pre-cutoff profile Pro only when the server policy says so", () => {
    const snapshot = buildTraxProEntitlementSnapshot(
      { is_pro: false, subscription_status: null },
      null,
      {
        profileCreatedAt: "2026-01-01T00:00:00.000Z",
        launchAccess: {
          launchAccessMode: "created_before_cutoff",
          launchAccessCutoffAt: "2026-06-01T00:00:00.000Z",
        },
      }
    )
    assert.equal(snapshot.traxProActive, true)
    assert.equal(snapshot.source, "launch_access")
    assert.equal(snapshot.accessExpiresAt, null)
  })
})

describe("cross-platform checkout", () => {
  it("does not offer Stripe when the server already reports Pro", () => {
    assert.equal(
      shouldOfferStripeCheckout({
        profileNeedsCheckout: true,
        serverTraxProActive: true,
      }),
      false
    )
  })

  it("still offers Stripe to a free profile when the server agrees", () => {
    assert.equal(
      shouldOfferStripeCheckout({
        profileNeedsCheckout: true,
        serverTraxProActive: false,
      }),
      true
    )
  })

  it("falls back to the profile gate when the entitlement request fails", () => {
    assert.equal(
      shouldOfferStripeCheckout({
        profileNeedsCheckout: false,
        serverTraxProActive: null,
      }),
      false
    )
  })
})

describe("appAccountToken binding", () => {
  it("accepts a matching token and rejects a different account", () => {
    const userId = "11111111-1111-4111-8111-111111111111"
    assert.equal(appleAppAccountTokenMatchesUser(userId, userId), true)
    assert.equal(appleAppAccountTokenMatchesUser(null, userId), true)
    assert.equal(
      appleAppAccountTokenMatchesUser(
        "22222222-2222-4222-8222-222222222222",
        userId
      ),
      false
    )
  })
})

describe("Apple root certificates", () => {
  it("loads Apple root CAs for SignedDataVerifier", () => {
    const certs = loadAppleRootCertificates()
    assert.equal(certs.length, 2)
    const subjects = certs.map((der) => new X509Certificate(der).subject)
    assert.ok(subjects.some((subject) => subject.includes("Apple Root CA - G3")))
    assert.ok(subjects.some((subject) => subject.includes("Apple Root CA - G2")))
  })
})
