import { Environment, NotificationTypeV2 } from "@apple/app-store-server-library"
import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "./database.types.ts"
import {
  applyVerifiedAppleSubscription,
  loadAppleSubscriptionByOriginalTransactionId,
  verifyAppleSignedNotification,
  verifyAppleSignedRenewalInfo,
  verifyAppleSignedTransactionInfo,
  type AppleSubscriptionRow,
} from "./appleSubscription.ts"

export type ProcessAppleNotificationResult =
  | { ok: true; duplicate: true }
  | { ok: true; duplicate: false; applied: boolean; originalTransactionId?: string }
  | { ok: false; status: number; reason: string }

async function recordNotificationIfNew(params: {
  supabase: SupabaseClient<Database>
  notificationUUID: string
  originalTransactionId: string | null
  notificationType: string
  subtype: string | null
  environment: string | null
  signedDateMs: number | null
}): Promise<{ duplicate: boolean }> {
  const { error } = await params.supabase
    .from("apple_subscription_notifications")
    .insert({
      notification_uuid: params.notificationUUID,
      original_transaction_id: params.originalTransactionId,
      notification_type: params.notificationType,
      subtype: params.subtype,
      environment: params.environment,
      signed_date: params.signedDateMs
        ? new Date(params.signedDateMs).toISOString()
        : null,
    })

  if (error?.code === "23505") {
    return { duplicate: true }
  }

  if (error) {
    throw new Error(error.message)
  }

  return { duplicate: false }
}

const STATEFUL_NOTIFICATION_TYPES = new Set<string>([
  NotificationTypeV2.SUBSCRIBED,
  NotificationTypeV2.DID_RENEW,
  NotificationTypeV2.DID_CHANGE_RENEWAL_STATUS,
  NotificationTypeV2.DID_CHANGE_RENEWAL_PREF,
  NotificationTypeV2.DID_FAIL_TO_RENEW,
  NotificationTypeV2.GRACE_PERIOD_EXPIRED,
  NotificationTypeV2.EXPIRED,
  NotificationTypeV2.REFUND,
  NotificationTypeV2.REVOKE,
  NotificationTypeV2.OFFER_REDEEMED,
  NotificationTypeV2.RENEWAL_EXTENDED,
  NotificationTypeV2.RENEWAL_EXTENSION,
  NotificationTypeV2.REFUND_REVERSED,
])

/**
 * Process a verified App Store Server Notification V2 payload.
 * Does not require a TradeTraxs user session.
 */
export async function processAppleSubscriptionNotification(params: {
  supabase: SupabaseClient<Database>
  signedPayload: string
}): Promise<ProcessAppleNotificationResult> {
  const verified = await verifyAppleSignedNotification(params.signedPayload)
  if (!verified.ok) {
    return { ok: false, status: 400, reason: verified.reason }
  }

  const { payload, environment } = verified
  const notificationUUID = payload.notificationUUID?.trim()
  const notificationType = String(payload.notificationType ?? "UNKNOWN")
  const subtype = payload.subtype ? String(payload.subtype) : null
  const signedDateMs = payload.signedDate ?? Date.now()

  if (!notificationUUID) {
    return { ok: false, status: 400, reason: "Missing notification UUID" }
  }

  const dataEnvironment =
    payload.data?.environment === Environment.SANDBOX ||
    payload.data?.environment === "Sandbox"
      ? "Sandbox"
      : payload.data?.environment === Environment.PRODUCTION ||
          payload.data?.environment === "Production"
        ? "Production"
        : environment === Environment.SANDBOX
          ? "Sandbox"
          : "Production"

  let originalTransactionId: string | null = null

  const signedTransactionInfo = payload.data?.signedTransactionInfo?.trim()
  if (signedTransactionInfo) {
    const txVerified = await verifyAppleSignedTransactionInfo(
      signedTransactionInfo,
      environment
    )
    if (txVerified.ok) {
      originalTransactionId = txVerified.transaction.originalTransactionId
    }
  }

  const idempotency = await recordNotificationIfNew({
    supabase: params.supabase,
    notificationUUID,
    originalTransactionId,
    notificationType,
    subtype,
    environment: dataEnvironment,
    signedDateMs,
  })

  if (idempotency.duplicate) {
    return { ok: true, duplicate: true }
  }

  if (notificationType === NotificationTypeV2.TEST) {
    return {
      ok: true,
      duplicate: false,
      applied: false,
      originalTransactionId: originalTransactionId ?? undefined,
    }
  }

  if (!STATEFUL_NOTIFICATION_TYPES.has(notificationType)) {
    return {
      ok: true,
      duplicate: false,
      applied: false,
      originalTransactionId: originalTransactionId ?? undefined,
    }
  }

  if (!signedTransactionInfo) {
    return {
      ok: true,
      duplicate: false,
      applied: false,
      originalTransactionId: originalTransactionId ?? undefined,
    }
  }

  const txVerified = await verifyAppleSignedTransactionInfo(
    signedTransactionInfo,
    environment
  )
  if (!txVerified.ok) {
    console.error(
      "[apple/subscription/notifications] transaction verify failed:",
      txVerified.reason
    )
    return { ok: false, status: 400, reason: txVerified.reason }
  }

  const transaction = txVerified.transaction
  originalTransactionId = transaction.originalTransactionId

  let renewal = undefined
  const signedRenewalInfo = payload.data?.signedRenewalInfo?.trim()
  if (signedRenewalInfo) {
    const renewalVerified = await verifyAppleSignedRenewalInfo(
      signedRenewalInfo,
      environment
    )
    if (renewalVerified.ok) {
      renewal = renewalVerified.renewal
    }
  }

  const existing: AppleSubscriptionRow | null =
    await loadAppleSubscriptionByOriginalTransactionId(
      params.supabase,
      transaction.originalTransactionId
    )

  if (!existing) {
    console.info(
      "[apple/subscription/notifications] no existing row for originalTransactionId=%s type=%s — acknowledged",
      transaction.originalTransactionId,
      notificationType
    )
    return {
      ok: true,
      duplicate: false,
      applied: false,
      originalTransactionId: transaction.originalTransactionId,
    }
  }

  const applied = await applyVerifiedAppleSubscription({
    supabase: params.supabase,
    userId: existing.user_id,
    transaction,
    renewal,
    notification: {
      notificationType,
      subtype: subtype ?? undefined,
      appleStatus:
        typeof payload.data?.status === "number"
          ? payload.data.status
          : undefined,
    },
    signedDateMs,
  })

  if (!applied.ok) {
    console.error(
      "[apple/subscription/notifications] apply failed:",
      applied.reason
    )
    return { ok: false, status: 500, reason: applied.reason }
  }

  return {
    ok: true,
    duplicate: false,
    applied: !applied.skipped,
    originalTransactionId: transaction.originalTransactionId,
  }
}
