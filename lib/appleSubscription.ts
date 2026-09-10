import {
  AppStoreServerAPIClient,
  Environment,
  SignedDataVerifier,
  type JWSTransactionDecodedPayload,
  type JWSRenewalInfoDecodedPayload,
  type ResponseBodyV2DecodedPayload,
} from "@apple/app-store-server-library"
import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "./database.types.ts"
import {
  resolveAppleSubscriptionStatus,
  resolveEffectiveExpiresAt,
  shouldApplyAppleSubscriptionUpdate,
  type AppleNotificationContext,
  type AppleRenewalContext,
} from "./appleSubscriptionState.ts"
import {
  isKnownTraxProAppleProductId,
  resolveTraxProBillingIntervalFromAppleProductId,
} from "./traxProProductIds.ts"

export type AppleSubscriptionStatus =
  | "active"
  | "expired"
  | "revoked"
  | "grace_period"
  | "billing_retry"

export type AppleSubscriptionRow = {
  id: string
  user_id: string
  original_transaction_id: string
  latest_transaction_id: string
  product_id: string
  environment: "Sandbox" | "Production"
  billing_interval: string | null
  status: AppleSubscriptionStatus
  expires_at: string | null
  revoked_at: string | null
  purchased_at: string | null
  last_verified_at: string
}

export type VerifiedAppleTransaction = {
  originalTransactionId: string
  transactionId: string
  productId: string
  environment: "Sandbox" | "Production"
  expiresAt: Date | null
  revokedAt: Date | null
  purchasedAt: Date | null
  revocationReason: number | null
  isUpgraded: boolean
}

export type VerifiedAppleRenewalInfo = AppleRenewalContext & {
  originalTransactionId?: string
  productId?: string
}

export type ApplyAppleSubscriptionParams = {
  supabase: SupabaseClient<Database>
  userId: string
  transaction: VerifiedAppleTransaction
  renewal?: VerifiedAppleRenewalInfo
  notification?: AppleNotificationContext
  /** Milliseconds since epoch from Apple signed payload — used for ordering. */
  signedDateMs?: number
}

export function isAppleSubscriptionActive(
  row: Pick<
    AppleSubscriptionRow,
    "status" | "expires_at" | "revoked_at"
  > | null | undefined,
  now: Date = new Date()
): boolean {
  if (!row) return false
  if (row.revoked_at) return false
  if (!["active", "grace_period", "billing_retry"].includes(row.status)) {
    return false
  }
  if (!row.expires_at) return true
  const expiresAt = new Date(row.expires_at)
  return !Number.isNaN(expiresAt.getTime()) && expiresAt > now
}

export function appleCredentialsConfigured(): boolean {
  return Boolean(
    process.env.APPLE_APP_STORE_ISSUER_ID?.trim() &&
      process.env.APPLE_APP_STORE_KEY_ID?.trim() &&
      process.env.APPLE_APP_STORE_PRIVATE_KEY?.trim() &&
      process.env.APPLE_BUNDLE_ID?.trim()
  )
}

function readApplePrivateKeyPem(): string {
  const raw = process.env.APPLE_APP_STORE_PRIVATE_KEY?.trim() ?? ""
  if (!raw) return ""
  if (raw.includes("BEGIN PRIVATE KEY")) {
    return raw.replace(/\\n/g, "\n")
  }
  return Buffer.from(raw, "base64").toString("utf8")
}

function mapEnvironment(
  environment: Environment
): "Sandbox" | "Production" {
  return environment === Environment.SANDBOX ? "Sandbox" : "Production"
}

function createVerifier(environment: Environment): SignedDataVerifier | null {
  const rootCerts: Buffer[] = []
  const bundleId = process.env.APPLE_BUNDLE_ID?.trim()
  const appAppleIdRaw = process.env.APPLE_APP_APPLE_ID?.trim()
  const appAppleId = appAppleIdRaw ? Number(appAppleIdRaw) : undefined

  if (!bundleId || !appleCredentialsConfigured()) return null

  try {
    return new SignedDataVerifier(
      rootCerts,
      true,
      environment,
      bundleId,
      appAppleId
    )
  } catch {
    return null
  }
}

export function mapDecodedTransaction(
  decoded: JWSTransactionDecodedPayload,
  environment: "Sandbox" | "Production"
): VerifiedAppleTransaction {
  const expiresMs = decoded.expiresDate ?? null
  const revokedMs = decoded.revocationDate ?? null
  const purchasedMs = decoded.purchaseDate ?? null

  return {
    originalTransactionId: String(decoded.originalTransactionId ?? ""),
    transactionId: String(decoded.transactionId ?? ""),
    productId: String(decoded.productId ?? ""),
    environment,
    expiresAt: expiresMs != null ? new Date(Number(expiresMs)) : null,
    revokedAt: revokedMs != null ? new Date(Number(revokedMs)) : null,
    purchasedAt: purchasedMs != null ? new Date(Number(purchasedMs)) : null,
    revocationReason: decoded.revocationReason ?? null,
    isUpgraded: decoded.isUpgraded === true,
  }
}

export function mapDecodedRenewalInfo(
  decoded: JWSRenewalInfoDecodedPayload
): VerifiedAppleRenewalInfo {
  const graceMs = decoded.gracePeriodExpiresDate ?? null
  return {
    originalTransactionId: decoded.originalTransactionId
      ? String(decoded.originalTransactionId)
      : undefined,
    productId: decoded.productId ? String(decoded.productId) : undefined,
    isInBillingRetryPeriod: decoded.isInBillingRetryPeriod === true,
    gracePeriodExpiresDate:
      graceMs != null ? new Date(Number(graceMs)) : null,
  }
}

function createAppStoreServerClient(
  environment: Environment
): AppStoreServerAPIClient | null {
  const signingKey = readApplePrivateKeyPem()
  const keyId = process.env.APPLE_APP_STORE_KEY_ID?.trim()
  const issuerId = process.env.APPLE_APP_STORE_ISSUER_ID?.trim()
  const bundleId = process.env.APPLE_BUNDLE_ID?.trim()
  if (!signingKey || !keyId || !issuerId || !bundleId) return null

  try {
    return new AppStoreServerAPIClient(
      signingKey,
      keyId,
      issuerId,
      bundleId,
      environment
    )
  } catch {
    return null
  }
}

export async function verifyAppleTransactionId(
  transactionId: string
): Promise<
  | { ok: true; transaction: VerifiedAppleTransaction }
  | { ok: false; reason: string }
> {
  const id = transactionId.trim()
  if (!id) {
    return { ok: false, reason: "Missing transaction id" }
  }

  if (!appleCredentialsConfigured()) {
    return { ok: false, reason: "Apple verification is not configured" }
  }

  for (const environment of [Environment.PRODUCTION, Environment.SANDBOX]) {
    const client = createAppStoreServerClient(environment)
    if (!client) {
      return { ok: false, reason: "Apple verifier unavailable" }
    }

    try {
      const response = await client.getTransactionInfo(id)
      const signed = response.signedTransactionInfo?.trim()
      if (!signed) continue
      const verified = await verifyAppleSignedTransactionInfo(signed)
      if (verified.ok) return verified
    } catch {
      // Try the other environment.
    }
  }

  return { ok: false, reason: "Transaction verification failed" }
}

export async function verifyAppleSignedTransactionInfo(
  signedTransactionInfo: string,
  preferredEnvironment?: Environment
): Promise<
  | { ok: true; transaction: VerifiedAppleTransaction }
  | { ok: false; reason: string }
> {
  const jws = signedTransactionInfo?.trim()
  if (!jws) {
    return { ok: false, reason: "Missing signed transaction" }
  }

  if (!appleCredentialsConfigured()) {
    return { ok: false, reason: "Apple verification is not configured" }
  }

  const attempts: Environment[] = preferredEnvironment
    ? [
        preferredEnvironment,
        preferredEnvironment === Environment.PRODUCTION
          ? Environment.SANDBOX
          : Environment.PRODUCTION,
      ]
    : [Environment.PRODUCTION, Environment.SANDBOX]

  for (const environment of attempts) {
    const verifier = createVerifier(environment)
    if (!verifier) {
      return { ok: false, reason: "Apple verifier unavailable" }
    }

    try {
      const decoded = await verifier.verifyAndDecodeTransaction(jws)
      const productId = String(decoded.productId ?? "")
      if (!isKnownTraxProAppleProductId(productId)) {
        return { ok: false, reason: "Unknown TraxPro product" }
      }

      const transaction = mapDecodedTransaction(
        decoded,
        mapEnvironment(environment)
      )
      if (!transaction.originalTransactionId || !transaction.transactionId) {
        return { ok: false, reason: "Invalid transaction identifiers" }
      }

      return { ok: true, transaction }
    } catch {
      // Try the other environment.
    }
  }

  return { ok: false, reason: "Transaction verification failed" }
}

export async function verifyAppleSignedRenewalInfo(
  signedRenewalInfo: string,
  preferredEnvironment?: Environment
): Promise<
  | { ok: true; renewal: VerifiedAppleRenewalInfo }
  | { ok: false; reason: string }
> {
  const jws = signedRenewalInfo?.trim()
  if (!jws) {
    return { ok: false, reason: "Missing signed renewal info" }
  }

  if (!appleCredentialsConfigured()) {
    return { ok: false, reason: "Apple verification is not configured" }
  }

  const attempts: Environment[] = preferredEnvironment
    ? [
        preferredEnvironment,
        preferredEnvironment === Environment.PRODUCTION
          ? Environment.SANDBOX
          : Environment.PRODUCTION,
      ]
    : [Environment.PRODUCTION, Environment.SANDBOX]

  for (const environment of attempts) {
    const verifier = createVerifier(environment)
    if (!verifier) {
      return { ok: false, reason: "Apple verifier unavailable" }
    }

    try {
      const decoded = await verifier.verifyAndDecodeRenewalInfo(jws)
      return { ok: true, renewal: mapDecodedRenewalInfo(decoded) }
    } catch {
      // Try the other environment.
    }
  }

  return { ok: false, reason: "Renewal verification failed" }
}

export async function verifyAppleSignedNotification(
  signedPayload: string
): Promise<
  | {
      ok: true
      payload: ResponseBodyV2DecodedPayload
      environment: Environment
    }
  | { ok: false; reason: string }
> {
  const jws = signedPayload?.trim()
  if (!jws) {
    return { ok: false, reason: "Missing signedPayload" }
  }

  if (!appleCredentialsConfigured()) {
    return { ok: false, reason: "Apple verification is not configured" }
  }

  for (const environment of [Environment.PRODUCTION, Environment.SANDBOX]) {
    const verifier = createVerifier(environment)
    if (!verifier) {
      return { ok: false, reason: "Apple verifier unavailable" }
    }

    try {
      const payload = await verifier.verifyAndDecodeNotification(jws)
      return { ok: true, payload, environment }
    } catch {
      // Try the other environment.
    }
  }

  return { ok: false, reason: "Notification verification failed" }
}

export async function loadAppleSubscriptionByOriginalTransactionId(
  supabase: SupabaseClient<Database>,
  originalTransactionId: string
): Promise<AppleSubscriptionRow | null> {
  const { data, error } = await supabase
    .from("apple_subscriptions")
    .select(
      "id,user_id,original_transaction_id,latest_transaction_id,product_id,environment,billing_interval,status,expires_at,revoked_at,purchased_at,last_verified_at"
    )
    .eq("original_transaction_id", originalTransactionId)
    .maybeSingle()

  if (error || !data) return null
  return data as AppleSubscriptionRow
}

export async function loadActiveAppleSubscriptionForUser(
  supabase: SupabaseClient<Database>,
  userId: string
): Promise<AppleSubscriptionRow | null> {
  const { data, error } = await supabase
    .from("apple_subscriptions")
    .select(
      "id,user_id,original_transaction_id,latest_transaction_id,product_id,environment,billing_interval,status,expires_at,revoked_at,purchased_at,last_verified_at"
    )
    .eq("user_id", userId)
    .order("expires_at", { ascending: false, nullsFirst: false })
    .limit(5)

  if (error || !data?.length) return null

  const active = data.find((row) =>
    isAppleSubscriptionActive(row as AppleSubscriptionRow)
  )
  return (active as AppleSubscriptionRow | undefined) ?? null
}

export async function assertAppleTransactionNotBoundToOtherUser(
  supabase: SupabaseClient<Database>,
  originalTransactionId: string,
  userId: string
): Promise<{ ok: true } | { ok: false; reason: string }> {
  const { data, error } = await supabase
    .from("apple_subscriptions")
    .select("user_id")
    .eq("original_transaction_id", originalTransactionId)
    .maybeSingle()

  if (error) {
    return { ok: false, reason: "Could not verify subscription ownership" }
  }

  if (data?.user_id && data.user_id !== userId) {
    return {
      ok: false,
      reason: "This App Store subscription belongs to another account",
    }
  }

  return { ok: true }
}

export async function applyVerifiedAppleSubscription(
  params: ApplyAppleSubscriptionParams
): Promise<
  | { ok: true; row: AppleSubscriptionRow; skipped: false }
  | { ok: true; row: AppleSubscriptionRow | null; skipped: true }
  | { ok: false; reason: string }
> {
  const { supabase, userId, transaction, renewal, notification } = params
  const signedDateMs =
    params.signedDateMs ?? Date.now()

  const existing = await loadAppleSubscriptionByOriginalTransactionId(
    supabase,
    transaction.originalTransactionId
  )

  if (existing && existing.user_id !== userId) {
    return {
      ok: false,
      reason: "This App Store subscription belongs to another account",
    }
  }

  const status = resolveAppleSubscriptionStatus(transaction, {
    renewal,
    notification,
  })
  const effectiveExpiresAt = resolveEffectiveExpiresAt(transaction, renewal)

  if (
    existing &&
    !shouldApplyAppleSubscriptionUpdate(existing, {
      transactionId: transaction.transactionId,
      signedDateMs,
      status,
    })
  ) {
    return { ok: true, row: existing, skipped: true }
  }

  const nowIso = new Date(signedDateMs).toISOString()
  const billingInterval = resolveTraxProBillingIntervalFromAppleProductId(
    transaction.productId
  )

  const payload = {
    user_id: userId,
    original_transaction_id: transaction.originalTransactionId,
    latest_transaction_id: transaction.transactionId,
    product_id: transaction.productId,
    environment: transaction.environment,
    billing_interval: billingInterval,
    status,
    expires_at: effectiveExpiresAt?.toISOString() ?? null,
    revoked_at: transaction.revokedAt?.toISOString() ?? null,
    purchased_at: transaction.purchasedAt?.toISOString() ?? null,
    last_verified_at: nowIso,
    updated_at: new Date().toISOString(),
  }

  const { data, error } = await supabase
    .from("apple_subscriptions")
    .upsert(payload, { onConflict: "original_transaction_id" })
    .select(
      "id,user_id,original_transaction_id,latest_transaction_id,product_id,environment,billing_interval,status,expires_at,revoked_at,purchased_at,last_verified_at"
    )
    .single()

  if (error || !data) {
    return {
      ok: false,
      reason: error?.message ?? "Failed to persist Apple subscription",
    }
  }

  return { ok: true, row: data as AppleSubscriptionRow, skipped: false }
}

export async function upsertVerifiedAppleSubscription(params: {
  supabase: SupabaseClient<Database>
  userId: string
  transaction: VerifiedAppleTransaction
}): Promise<AppleSubscriptionRow> {
  const result = await applyVerifiedAppleSubscription({
    supabase: params.supabase,
    userId: params.userId,
    transaction: params.transaction,
    signedDateMs: Date.now(),
  })

  if (!result.ok) {
    throw new Error(result.reason)
  }

  if (!result.row) {
    throw new Error("Failed to persist Apple subscription")
  }

  return result.row
}
