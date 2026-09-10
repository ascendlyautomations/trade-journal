import { Status } from "@apple/app-store-server-library"
import type {
  AppleSubscriptionRow,
  AppleSubscriptionStatus,
  VerifiedAppleTransaction,
} from "./appleSubscription.ts"

export type AppleRenewalContext = {
  isInBillingRetryPeriod?: boolean
  gracePeriodExpiresDate?: Date | null
}

export type AppleNotificationContext = {
  notificationType?: string
  subtype?: string
  /** App Store `data.status` when present on the notification. */
  appleStatus?: number
}

export function resolveEffectiveExpiresAt(
  tx: VerifiedAppleTransaction,
  renewal?: AppleRenewalContext
): Date | null {
  const candidates: Date[] = []
  if (tx.expiresAt) candidates.push(tx.expiresAt)
  if (renewal?.gracePeriodExpiresDate) {
    candidates.push(renewal.gracePeriodExpiresDate)
  }
  if (!candidates.length) return null
  return new Date(Math.max(...candidates.map((d) => d.getTime())))
}

/**
 * Authoritative Apple subscription status mapping shared by client sync and ASSN V2.
 */
export function resolveAppleSubscriptionStatus(
  tx: VerifiedAppleTransaction,
  contexts?: {
    renewal?: AppleRenewalContext
    notification?: AppleNotificationContext
  },
  now: Date = new Date()
): AppleSubscriptionStatus {
  const renewal = contexts?.renewal
  const notification = contexts?.notification

  if (tx.revokedAt) return "revoked"

  if (
    notification?.notificationType === "REFUND" ||
    notification?.notificationType === "REVOKE"
  ) {
    return "revoked"
  }

  if (notification?.appleStatus === Status.REVOKED) return "revoked"
  if (notification?.appleStatus === Status.EXPIRED) return "expired"
  if (notification?.appleStatus === Status.BILLING_GRACE_PERIOD) {
    return "grace_period"
  }
  if (notification?.appleStatus === Status.BILLING_RETRY) {
    return "billing_retry"
  }

  if (notification?.notificationType === "GRACE_PERIOD_EXPIRED") return "expired"
  if (notification?.notificationType === "EXPIRED") return "expired"

  if (tx.isUpgraded) return "expired"

  const effectiveExpiresAt = resolveEffectiveExpiresAt(tx, renewal)

  if (renewal?.gracePeriodExpiresDate && renewal.gracePeriodExpiresDate > now) {
    return "grace_period"
  }

  if (notification?.notificationType === "DID_FAIL_TO_RENEW") {
    if (notification.subtype === "GRACE_PERIOD") return "grace_period"
    if (renewal?.isInBillingRetryPeriod) return "billing_retry"
  }

  if (renewal?.isInBillingRetryPeriod) {
    if (!effectiveExpiresAt || effectiveExpiresAt > now) {
      return "billing_retry"
    }
  }

  if (effectiveExpiresAt && effectiveExpiresAt <= now) {
    return "expired"
  }

  return "active"
}

export function shouldApplyAppleSubscriptionUpdate(
  existing: Pick<
    AppleSubscriptionRow,
    "latest_transaction_id" | "last_verified_at" | "status"
  > | null,
  incoming: {
    transactionId: string
    signedDateMs: number
    status: AppleSubscriptionStatus
  }
): boolean {
  if (!existing) return true

  const existingVerifiedMs = new Date(existing.last_verified_at).getTime()
  if (Number.isFinite(incoming.signedDateMs)) {
    if (incoming.signedDateMs > existingVerifiedMs) return true
    if (incoming.signedDateMs < existingVerifiedMs) return false
  }

  try {
    const existingTxId = BigInt(existing.latest_transaction_id || "0")
    const incomingTxId = BigInt(incoming.transactionId || "0")
    if (incomingTxId > existingTxId) return true
    if (incomingTxId < existingTxId) return false
  } catch {
    if (incoming.transactionId !== existing.latest_transaction_id) {
      return incoming.transactionId > existing.latest_transaction_id
    }
  }

  const terminal: AppleSubscriptionStatus[] = ["revoked", "expired"]
  if (terminal.includes(incoming.status) && existing.status !== incoming.status) {
    return true
  }

  return incoming.status !== existing.status
}
