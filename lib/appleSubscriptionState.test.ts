import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { NotificationTypeV2, Status, Subtype } from "@apple/app-store-server-library"
import {
  resolveAppleSubscriptionStatus,
  resolveEffectiveExpiresAt,
  shouldApplyAppleSubscriptionUpdate,
} from "./appleSubscriptionState.ts"
import type { VerifiedAppleTransaction } from "./appleSubscription.ts"

const now = new Date("2026-06-01T12:00:00.000Z")
const future = new Date("2026-07-01T12:00:00.000Z")
const past = new Date("2026-05-01T12:00:00.000Z")

function tx(
  overrides: Partial<VerifiedAppleTransaction> = {}
): VerifiedAppleTransaction {
  return {
    originalTransactionId: "otid-1",
    transactionId: "100",
    productId: "com.tradetraxs.traxpro.monthly",
    environment: "Sandbox",
    expiresAt: future,
    revokedAt: null,
    purchasedAt: past,
    revocationReason: null,
    isUpgraded: false,
    ...overrides,
  }
}

describe("resolveAppleSubscriptionStatus", () => {
  it("returns active for unexpired verified renewal", () => {
    assert.equal(
      resolveAppleSubscriptionStatus(tx(), undefined, now),
      "active"
    )
  })

  it("returns active on DID_RENEW", () => {
    assert.equal(
      resolveAppleSubscriptionStatus(tx({ transactionId: "101" }), {
        notification: { notificationType: NotificationTypeV2.DID_RENEW },
      }, now),
      "active"
    )
  })

  it("does not revoke immediately when auto-renew disabled", () => {
    assert.equal(
      resolveAppleSubscriptionStatus(tx(), {
        notification: {
          notificationType: NotificationTypeV2.DID_CHANGE_RENEWAL_STATUS,
          subtype: Subtype.AUTO_RENEW_DISABLED,
        },
        renewal: { isInBillingRetryPeriod: false },
      }, now),
      "active"
    )
  })

  it("returns grace_period during billing grace", () => {
    assert.equal(
      resolveAppleSubscriptionStatus(
        tx({ expiresAt: past }),
        {
          notification: {
            notificationType: NotificationTypeV2.DID_FAIL_TO_RENEW,
            subtype: Subtype.GRACE_PERIOD,
          },
          renewal: { gracePeriodExpiresDate: future },
        },
        now
      ),
      "grace_period"
    )
  })

  it("returns billing_retry when Apple reports billing retry", () => {
    assert.equal(
      resolveAppleSubscriptionStatus(tx(), {
        notification: { appleStatus: Status.BILLING_RETRY },
        renewal: { isInBillingRetryPeriod: true },
      }, now),
      "billing_retry"
    )
  })

  it("returns expired after grace period expired notification", () => {
    assert.equal(
      resolveAppleSubscriptionStatus(tx({ expiresAt: past }), {
        notification: { notificationType: NotificationTypeV2.GRACE_PERIOD_EXPIRED },
      }, now),
      "expired"
    )
  })

  it("returns expired when past expiration", () => {
    assert.equal(
      resolveAppleSubscriptionStatus(tx({ expiresAt: past }), undefined, now),
      "expired"
    )
  })

  it("returns revoked on refund notification", () => {
    assert.equal(
      resolveAppleSubscriptionStatus(tx(), {
        notification: { notificationType: NotificationTypeV2.REFUND },
      }, now),
      "revoked"
    )
  })

  it("returns revoked when transaction has revocation date", () => {
    assert.equal(
      resolveAppleSubscriptionStatus(tx({ revokedAt: past }), undefined, now),
      "revoked"
    )
  })
})

describe("resolveEffectiveExpiresAt", () => {
  it("extends expires_at with grace period date", () => {
    const effective = resolveEffectiveExpiresAt(
      tx({ expiresAt: past }),
      { gracePeriodExpiresDate: future }
    )
    assert.equal(effective?.toISOString(), future.toISOString())
  })
})

describe("shouldApplyAppleSubscriptionUpdate", () => {
  it("rejects older signed notifications", () => {
    assert.equal(
      shouldApplyAppleSubscriptionUpdate(
        {
          latest_transaction_id: "200",
          last_verified_at: "2026-06-02T00:00:00.000Z",
          status: "active",
        },
        {
          transactionId: "199",
          signedDateMs: new Date("2026-06-01T00:00:00.000Z").getTime(),
          status: "active",
        }
      ),
      false
    )
  })

  it("accepts newer transaction ids at same signed date", () => {
    const signed = new Date("2026-06-02T00:00:00.000Z").getTime()
    assert.equal(
      shouldApplyAppleSubscriptionUpdate(
        {
          latest_transaction_id: "200",
          last_verified_at: "2026-06-02T00:00:00.000Z",
          status: "active",
        },
        {
          transactionId: "201",
          signedDateMs: signed,
          status: "active",
        }
      ),
      true
    )
  })

  it("accepts terminal revoke over stale active", () => {
    const signed = new Date("2026-06-02T00:00:00.000Z").getTime()
    assert.equal(
      shouldApplyAppleSubscriptionUpdate(
        {
          latest_transaction_id: "200",
          last_verified_at: "2026-06-02T00:00:00.000Z",
          status: "active",
        },
        {
          transactionId: "200",
          signedDateMs: signed,
          status: "revoked",
        }
      ),
      true
    )
  })
})
