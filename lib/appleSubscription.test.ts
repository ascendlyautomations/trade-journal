import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { Environment, VerificationStatus } from "@apple/app-store-server-library"
import {
  getTraxProAppleProductIdSet,
  isKnownTraxProAppleProductId,
  resolveTraxProBillingIntervalFromAppleProductId,
} from "./traxProProductIds.ts"
import {
  appleVerificationEnvironments,
  buildAppleSyncRequestDiagnostics,
  isAppleSubscriptionActive,
  isStoreKitTestingEnvironmentClaim,
  readUnverifiedAppleTransactionClaims,
  shouldRetryAppleVerificationWithoutOnlineChecks,
} from "./appleSubscription.ts"

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

describe("Apple transaction verification targeting", () => {
  it("tries the claimed Apple environment before the other one", () => {
    assert.deepEqual(appleVerificationEnvironments("Sandbox"), [
      Environment.SANDBOX,
      Environment.PRODUCTION,
    ])
    assert.deepEqual(appleVerificationEnvironments("Production"), [
      Environment.PRODUCTION,
      Environment.SANDBOX,
    ])
  })

  it("does not select the Xcode verifier for StoreKit configuration transactions", () => {
    const attempts = appleVerificationEnvironments("Xcode")
    assert.equal(attempts.includes(Environment.XCODE), false)
    assert.equal(attempts.includes(Environment.LOCAL_TESTING), false)
    assert.deepEqual(attempts, [Environment.PRODUCTION, Environment.SANDBOX])
  })

  it("reads safe claims from a JWS payload and ignores the signature", () => {
    const payload = Buffer.from(
      JSON.stringify({
        environment: "Sandbox",
        productId: "com.tradetraxs.traxspro.monthly",
        bundleId: "com.tradetraxs.TradeTraxs",
        transactionId: "2000000123456789",
      })
    ).toString("base64url")
    const claims = readUnverifiedAppleTransactionClaims(
      `eyJhbGciOiJFUzI1NiJ9.${payload}.signature`
    )
    assert.deepEqual(claims, {
      environment: "Sandbox",
      productId: "com.tradetraxs.traxspro.monthly",
      bundleId: "com.tradetraxs.TradeTraxs",
      transactionId: "2000000123456789",
    })
  })

  it("retries certificate failures without OCSP and keeps environment mismatches definitive", () => {
    assert.equal(
      shouldRetryAppleVerificationWithoutOnlineChecks(
        VerificationStatus.VERIFICATION_FAILURE
      ),
      true
    )
    assert.equal(
      shouldRetryAppleVerificationWithoutOnlineChecks(VerificationStatus.FAILURE),
      true
    )
    assert.equal(
      shouldRetryAppleVerificationWithoutOnlineChecks(
        VerificationStatus.INVALID_ENVIRONMENT
      ),
      false
    )
    assert.equal(
      shouldRetryAppleVerificationWithoutOnlineChecks(
        VerificationStatus.INVALID_APP_IDENTIFIER
      ),
      false
    )
  })
})

describe("verifyAppleSignedTransactionInfo", () => {
  it("rejects a forged sandbox payload instead of trusting its claims", async () => {
    const keys = [
      "APPLE_APP_STORE_ISSUER_ID",
      "APPLE_APP_STORE_KEY_ID",
      "APPLE_APP_STORE_PRIVATE_KEY",
      "APPLE_BUNDLE_ID",
      "APPLE_APP_APPLE_ID",
    ] as const
    const previous = Object.fromEntries(keys.map((key) => [key, process.env[key]]))
    process.env.APPLE_APP_STORE_ISSUER_ID = "00000000-0000-0000-0000-000000000000"
    process.env.APPLE_APP_STORE_KEY_ID = "TESTKEY123"
    process.env.APPLE_APP_STORE_PRIVATE_KEY = "not-a-real-key"
    process.env.APPLE_BUNDLE_ID = "com.tradetraxs.TradeTraxs"
    process.env.APPLE_APP_APPLE_ID = "1234567890"
    try {
      const { verifyAppleSignedTransactionInfo } = await import(
        "./appleSubscription.ts"
      )
      const payload = Buffer.from(
        JSON.stringify({
          environment: "Sandbox",
          productId: "com.tradetraxs.traxspro.monthly",
          bundleId: "com.tradetraxs.TradeTraxs",
          transactionId: "1",
          originalTransactionId: "1",
        })
      ).toString("base64url")
      const result = await verifyAppleSignedTransactionInfo(`e30.${payload}.sig`)
      assert.equal(result.ok, false)
      if (!result.ok) {
        assert.equal(result.reason, "Transaction verification failed")
      }
    } finally {
      for (const key of keys) {
        const value = previous[key]
        if (value == null) delete process.env[key]
        else process.env[key] = value
      }
    }
  })

  it("rejects Xcode StoreKit Testing claims before JWS verification", async () => {
    const keys = [
      "APPLE_APP_STORE_ISSUER_ID",
      "APPLE_APP_STORE_KEY_ID",
      "APPLE_APP_STORE_PRIVATE_KEY",
      "APPLE_BUNDLE_ID",
      "APPLE_APP_APPLE_ID",
    ] as const
    const previous = Object.fromEntries(keys.map((key) => [key, process.env[key]]))
    process.env.APPLE_APP_STORE_ISSUER_ID = "00000000-0000-0000-0000-000000000000"
    process.env.APPLE_APP_STORE_KEY_ID = "TESTKEY123"
    process.env.APPLE_APP_STORE_PRIVATE_KEY = "not-a-real-key"
    process.env.APPLE_BUNDLE_ID = "com.tradetraxs.TradeTraxs"
    process.env.APPLE_APP_APPLE_ID = "1234567890"
    try {
      const { verifyAppleSignedTransactionInfo } = await import(
        "./appleSubscription.ts"
      )
      const payload = Buffer.from(
        JSON.stringify({
          environment: "Xcode",
          productId: "com.tradetraxs.traxspro.monthly",
          bundleId: "com.tradetraxs.TradeTraxs",
          transactionId: "local-1",
        })
      ).toString("base64url")
      const result = await verifyAppleSignedTransactionInfo(`e30.${payload}.sig`)
      assert.equal(result.ok, false)
      if (!result.ok) {
        assert.equal(result.clientCode, "STOREKIT_TESTING_NOT_VERIFIABLE")
      }
    } finally {
      for (const key of keys) {
        const value = previous[key]
        if (value == null) delete process.env[key]
        else process.env[key] = value
      }
    }
  })

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
      "com.tradetraxs.traxpro.sixmonth",
      "com.tradetraxs.traxpro.yearly",
      "com.tradetraxs.traxspro.monthly",
    ])
    assert.equal(
      isKnownTraxProAppleProductId("com.tradetraxs.traxspro.monthly"),
      true
    )
    assert.equal(
      resolveTraxProBillingIntervalFromAppleProductId(
        "com.tradetraxs.traxspro.monthly"
      ),
      "monthly"
    )
    assert.equal(
      isKnownTraxProAppleProductId("com.tradetraxs.traxpro.monthly"),
      false
    )
    assert.equal(
      resolveTraxProBillingIntervalFromAppleProductId(
        "com.tradetraxs.traxpro.monthly"
      ),
      null
    )
  })
})

describe("Apple sync diagnostics", () => {
  it("flags StoreKit Testing claims without logging JWS contents", () => {
    const payload = Buffer.from(
      JSON.stringify({
        environment: "Xcode",
        productId: "com.tradetraxs.traxspro.monthly",
        bundleId: "com.tradetraxs.TradeTraxs",
      })
    ).toString("base64url")
    const jws = `e30.${payload}.sig`
    assert.equal(isStoreKitTestingEnvironmentClaim("Xcode"), true)
    const diagnostics = buildAppleSyncRequestDiagnostics({
      signedTransactionInfo: jws,
      transactionId: "123",
    })
    assert.equal(diagnostics.hasSignedTransactionInfo, true)
    assert.equal(diagnostics.appearsStoreKitTestingClaim, true)
    assert.equal(diagnostics.claimedEnvironment, "Xcode")
    assert.equal(diagnostics.bundleIdMatchesConfig, null)
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
