import {
  APIException,
  AppStoreServerAPIClient,
  Environment,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
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
import { appleAppAccountTokenMatchesUser } from "./monetizationConfig.ts"
import { loadAppleRootCertificates } from "./appleRootCertificates.ts"
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
  /** Apple appAccountToken, when the purchase was bound to a TradeTraxs user id. */
  appAccountToken: string | null
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

export type UnverifiedAppleTransactionClaims = {
  environment?: string
  productId?: string
  bundleId?: string
  transactionId?: string
}

export const STOREKIT_TESTING_NOT_VERIFIABLE_REASON =
  "StoreKit Testing transactions cannot be verified by the server"

export function isStoreKitTestingEnvironmentClaim(
  environment: string | undefined
): boolean {
  return (
    environment === Environment.XCODE ||
    environment === Environment.LOCAL_TESTING
  )
}

/** Safe request metadata for `/api/apple/subscription/sync` logs — never includes full JWS. */
export type AppleSyncRequestDiagnostics = {
  hasSignedTransactionInfo: boolean
  signedTransactionInfoLength: number
  hasTransactionId: boolean
  claimedEnvironment?: string
  claimedProductId?: string
  claimedBundleId?: string
  claimedTransactionId?: string
  configuredBundleId?: string
  bundleIdMatchesConfig: boolean | null
  certificateStage: string
  x5cCount?: number
  appearsStoreKitTestingClaim: boolean
  credentialsConfigured: boolean
}

export function buildAppleSyncRequestDiagnostics(input: {
  signedTransactionInfo?: string | null
  transactionId?: string | null
}): AppleSyncRequestDiagnostics {
  const signed = input.signedTransactionInfo?.trim() ?? ""
  const claims = signed ? readUnverifiedAppleTransactionClaims(signed) : null
  const certificate = signed
    ? readJWSCertificateStage(signed)
    : { certificateStage: "missing_jws" as const }
  const configuredBundleId = process.env.APPLE_BUNDLE_ID?.trim()
  const claimedBundleId = claims?.bundleId
  const bundleIdMatchesConfig =
    claimedBundleId && configuredBundleId
      ? claimedBundleId === configuredBundleId
      : null

  return {
    hasSignedTransactionInfo: signed.length > 0,
    signedTransactionInfoLength: signed.length,
    hasTransactionId: Boolean(input.transactionId?.trim()),
    claimedEnvironment: claims?.environment,
    claimedProductId: claims?.productId,
    claimedBundleId,
    claimedTransactionId: claims?.transactionId,
    configuredBundleId,
    bundleIdMatchesConfig,
    certificateStage: certificate.certificateStage,
    x5cCount: certificate.x5cCount,
    appearsStoreKitTestingClaim: isStoreKitTestingEnvironmentClaim(
      claims?.environment
    ),
    credentialsConfigured: appleCredentialsConfigured(),
  }
}

/**
 * Reads the unsigned JWT payload so verification can target Sandbox vs Production.
 * These claims are never used to grant access.
 */
export function readUnverifiedAppleTransactionClaims(
  jws: string
): UnverifiedAppleTransactionClaims | null {
  const payload = jws.split(".")[1]
  if (!payload) return null
  try {
    const decoded = JSON.parse(
      Buffer.from(payload, "base64url").toString("utf8")
    ) as Record<string, unknown>
    if (!decoded || typeof decoded !== "object") return null
    return {
      environment:
        typeof decoded.environment === "string" ? decoded.environment : undefined,
      productId:
        typeof decoded.productId === "string" ? decoded.productId : undefined,
      bundleId:
        typeof decoded.bundleId === "string" ? decoded.bundleId : undefined,
      transactionId:
        typeof decoded.transactionId === "string"
          ? decoded.transactionId
          : undefined,
    }
  } catch {
    return null
  }
}

/** Apple-signed environments only. Xcode and LocalTesting are not verifier targets. */
export function appleVerificationEnvironments(
  claimedEnvironment: string | undefined
): Environment[] {
  if (claimedEnvironment === Environment.SANDBOX) {
    return [Environment.SANDBOX, Environment.PRODUCTION]
  }
  if (claimedEnvironment === Environment.PRODUCTION) {
    return [Environment.PRODUCTION, Environment.SANDBOX]
  }
  return [Environment.PRODUCTION, Environment.SANDBOX]
}

/**
 * Chain and signature failures are retried once without OCSP.
 * Environment and bundle mismatches are definitive for that verifier.
 */
export function shouldRetryAppleVerificationWithoutOnlineChecks(
  status: VerificationStatus
): boolean {
  return (
    status !== VerificationStatus.INVALID_ENVIRONMENT &&
    status !== VerificationStatus.INVALID_APP_IDENTIFIER
  )
}

type AppleVerificationLog = {
  stage: string
  appleEnvironment?: string
  productId?: string
  bundleId?: string
  configuredBundleId?: string
  transactionId?: string
  verificationStatus?: string
  apiStatusCode?: number
  apiErrorCode?: number | null
  certificateStage?: string
  x5cCount?: number
  onlineChecks?: boolean
  cause?: string
  transactionIdFallbackAttempted?: boolean
  verifierUsed?: "SignedDataVerifier" | "AppStoreServerAPI"
}

function logAppleVerification(details: AppleVerificationLog) {
  console.error("[apple-subscription-verify]", details)
}

function sanitizeDiagnostic(value: string | null | undefined): string | undefined {
  if (!value) return undefined
  if (
    value.includes("BEGIN ") ||
    value.includes("eyJ") ||
    value.length > 160
  ) {
    return "omitted"
  }
  return value
}

function verificationFailureDetails(error: unknown): Pick<
  AppleVerificationLog,
  "verificationStatus" | "apiStatusCode" | "apiErrorCode" | "cause"
> {
  if (error instanceof VerificationException) {
    const cause = error.cause instanceof Error ? error.cause.message : undefined
    return {
      verificationStatus: VerificationStatus[error.status] ?? String(error.status),
      cause: sanitizeDiagnostic(cause),
    }
  }
  if (error instanceof APIException) {
    return {
      apiStatusCode: error.httpStatusCode,
      apiErrorCode: error.apiError == null ? null : Number(error.apiError),
      cause: sanitizeDiagnostic(error.errorMessage),
    }
  }
  if (error instanceof Error) {
    return { cause: sanitizeDiagnostic(`${error.name}`) }
  }
  return { cause: "unknown_error" }
}

function readJWSCertificateStage(jws: string): {
  x5cCount?: number
  certificateStage: string
} {
  const headerPart = jws.split(".")[0]
  if (!headerPart) return { certificateStage: "missing_header" }
  try {
    const header = JSON.parse(
      Buffer.from(headerPart, "base64url").toString("utf8")
    ) as { x5c?: unknown }
    const x5cCount = Array.isArray(header.x5c) ? header.x5c.length : 0
    return {
      x5cCount,
      certificateStage: x5cCount === 3 ? "x5c_chain_present" : "x5c_chain_length",
    }
  } catch {
    return { certificateStage: "header_decode_failed" }
  }
}

function verifierUnavailableReason(environment: Environment): string | null {
  if (!process.env.APPLE_BUNDLE_ID?.trim() || !appleCredentialsConfigured()) {
    return "credentials_or_bundle_missing"
  }
  if (environment === Environment.PRODUCTION) {
    const appAppleId = Number(process.env.APPLE_APP_APPLE_ID?.trim())
    if (!Number.isFinite(appAppleId)) return "production_app_apple_id_missing"
  }
  try {
    if (loadAppleRootCertificates().length === 0) {
      return "apple_root_certificates_missing"
    }
  } catch {
    return "apple_root_certificates_invalid"
  }
  return null
}

function createVerifier(
  environment: Environment,
  enableOnlineChecks: boolean
): SignedDataVerifier | null {
  const bundleId = process.env.APPLE_BUNDLE_ID?.trim()
  const appAppleIdRaw = process.env.APPLE_APP_APPLE_ID?.trim()
  const appAppleId = appAppleIdRaw ? Number(appAppleIdRaw) : undefined

  if (!bundleId || !appleCredentialsConfigured()) return null
  if (environment === Environment.PRODUCTION && !Number.isFinite(appAppleId)) {
    return null
  }

  let rootCerts: Buffer[]
  try {
    rootCerts = loadAppleRootCertificates()
  } catch {
    return null
  }
  if (rootCerts.length === 0) return null

  try {
    return new SignedDataVerifier(
      rootCerts,
      enableOnlineChecks,
      environment,
      bundleId,
      environment === Environment.PRODUCTION ? appAppleId : undefined
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
    appAccountToken: decoded.appAccountToken
      ? String(decoded.appAccountToken)
      : null,
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
    logAppleVerification({
      stage: "credentials",
      transactionId: id,
      cause: "apple_app_store_credentials_or_bundle_missing",
    })
    return { ok: false, reason: "Apple verification is not configured" }
  }

  let sawSignedTransaction = false
  for (const environment of [Environment.PRODUCTION, Environment.SANDBOX]) {
    const client = createAppStoreServerClient(environment)
    if (!client) {
      logAppleVerification({
        stage: "app_store_server_api",
        appleEnvironment: environment,
        transactionId: id,
        cause: "api_client_unavailable",
      })
      continue
    }

    try {
      const response = await client.getTransactionInfo(id)
      const signed = response.signedTransactionInfo?.trim()
      if (!signed) {
        logAppleVerification({
          stage: "app_store_server_api",
          appleEnvironment: environment,
          transactionId: id,
          cause: "missing_signed_transaction_info",
        })
        continue
      }
      sawSignedTransaction = true
      const verified = await verifyAppleSignedTransactionInfo(signed, environment)
      if (verified.ok) return verified
      logAppleVerification({
        stage: "transaction_id_fallback_jws_rejected",
        appleEnvironment: environment,
        transactionId: id,
        transactionIdFallbackAttempted: true,
        verifierUsed: "AppStoreServerAPI",
        cause: verified.ok ? undefined : verified.reason,
      })
    } catch (error) {
      logAppleVerification({
        stage: "app_store_server_api",
        appleEnvironment: environment,
        transactionId: id,
        ...verificationFailureDetails(error),
      })
    }
  }

  if (!sawSignedTransaction) {
    logAppleVerification({
      stage: "app_store_server_api",
      transactionId: id,
      cause: "transaction_not_returned_for_production_or_sandbox",
    })
  }

  return { ok: false, reason: "Transaction verification failed" }
}

async function verifyDecodedAppleTransaction(
  jws: string,
  environment: Environment,
  enableOnlineChecks: boolean
): Promise<
  | { ok: true; transaction: VerifiedAppleTransaction }
  | { ok: false; reason: string }
  | { ok: false; retryWithoutOnlineChecks: true }
> {
  const unavailable = verifierUnavailableReason(environment)
  const verifier = unavailable ? null : createVerifier(environment, enableOnlineChecks)
  const claims = readUnverifiedAppleTransactionClaims(jws)
  const certificate = readJWSCertificateStage(jws)
  if (!verifier) {
    logAppleVerification({
      stage: "verifier_unavailable",
      appleEnvironment: environment,
      productId: claims?.productId,
      bundleId: claims?.bundleId,
      configuredBundleId: process.env.APPLE_BUNDLE_ID?.trim(),
      transactionId: claims?.transactionId,
      certificateStage: certificate.certificateStage,
      x5cCount: certificate.x5cCount,
      onlineChecks: enableOnlineChecks,
      cause: unavailable ?? "signed_data_verifier_init_failed",
    })
    return { ok: false, reason: "Transaction verification failed" }
  }

  try {
    const decoded = await verifier.verifyAndDecodeTransaction(jws)
    const productId = String(decoded.productId ?? "")
    if (!isKnownTraxProAppleProductId(productId)) {
      logAppleVerification({
        stage: "product_id",
        appleEnvironment: mapEnvironment(environment),
        productId,
        bundleId: decoded.bundleId,
        configuredBundleId: process.env.APPLE_BUNDLE_ID?.trim(),
        transactionId: decoded.transactionId,
        onlineChecks: enableOnlineChecks,
      })
      return { ok: false, reason: "Unknown TraxPro product" }
    }

    const transaction = mapDecodedTransaction(decoded, mapEnvironment(environment))
    if (!transaction.originalTransactionId || !transaction.transactionId) {
      logAppleVerification({
        stage: "transaction_identifiers",
        appleEnvironment: transaction.environment,
        productId: transaction.productId,
        bundleId: decoded.bundleId,
        transactionId: transaction.transactionId || undefined,
        onlineChecks: enableOnlineChecks,
      })
      return { ok: false, reason: "Invalid transaction identifiers" }
    }

    return { ok: true, transaction }
  } catch (error) {
    const failure = verificationFailureDetails(error)
    logAppleVerification({
      stage: "jws_verification",
      appleEnvironment: environment,
      productId: claims?.productId,
      bundleId: claims?.bundleId,
      configuredBundleId: process.env.APPLE_BUNDLE_ID?.trim(),
      transactionId: claims?.transactionId,
      certificateStage: certificate.certificateStage,
      x5cCount: certificate.x5cCount,
      onlineChecks: enableOnlineChecks,
      ...failure,
    })
    if (
      enableOnlineChecks &&
      error instanceof VerificationException &&
      shouldRetryAppleVerificationWithoutOnlineChecks(error.status)
    ) {
      return { ok: false, retryWithoutOnlineChecks: true }
    }
    return { ok: false, reason: "Transaction verification failed" }
  }
}

export type AppleSignedTransactionVerifyResult =
  | { ok: true; transaction: VerifiedAppleTransaction }
  | {
      ok: false
      reason: string
      clientCode?:
        | "STOREKIT_TESTING_NOT_VERIFIABLE"
        | "APPLE_BUNDLE_MISMATCH"
        | "APPLE_NOT_CONFIGURED"
        | "UNKNOWN_PRODUCT"
        | "VERIFICATION_FAILED"
    }

export async function verifyAppleSignedTransactionInfo(
  signedTransactionInfo: string,
  preferredEnvironment?: Environment
): Promise<AppleSignedTransactionVerifyResult> {
  const jws = signedTransactionInfo?.trim()
  if (!jws) {
    return { ok: false, reason: "Missing signed transaction", clientCode: "VERIFICATION_FAILED" }
  }

  if (!appleCredentialsConfigured()) {
    logAppleVerification({
      stage: "credentials",
      cause: "apple_app_store_credentials_or_bundle_missing",
      ...readJWSCertificateStage(jws),
    })
    return {
      ok: false,
      reason: "Apple verification is not configured",
      clientCode: "APPLE_NOT_CONFIGURED",
    }
  }

  const claims = readUnverifiedAppleTransactionClaims(jws)
  const configuredBundleId = process.env.APPLE_BUNDLE_ID?.trim()
  if (
    claims?.bundleId &&
    configuredBundleId &&
    claims.bundleId !== configuredBundleId
  ) {
    logAppleVerification({
      stage: "bundle_mismatch",
      appleEnvironment: claims.environment,
      productId: claims.productId,
      bundleId: claims.bundleId,
      configuredBundleId,
      transactionId: claims.transactionId,
      ...readJWSCertificateStage(jws),
      cause: "jws_bundle_id_does_not_match_server_config",
    })
    return {
      ok: false,
      reason: "Transaction bundle ID does not match server configuration",
      clientCode: "APPLE_BUNDLE_MISMATCH",
    }
  }

  if (isStoreKitTestingEnvironmentClaim(claims?.environment)) {
    logAppleVerification({
      stage: "environment",
      appleEnvironment: claims?.environment,
      productId: claims?.productId,
      bundleId: claims?.bundleId,
      configuredBundleId,
      transactionId: claims?.transactionId,
      ...readJWSCertificateStage(jws),
      cause: "storekit_testing_transaction_is_not_apple_signed",
    })
    return {
      ok: false,
      reason: STOREKIT_TESTING_NOT_VERIFIABLE_REASON,
      clientCode: "STOREKIT_TESTING_NOT_VERIFIABLE",
    }
  }

  const attempts = preferredEnvironment
    ? appleVerificationEnvironments(preferredEnvironment)
    : appleVerificationEnvironments(claims?.environment)

  for (const environment of attempts) {
    const online = await verifyDecodedAppleTransaction(jws, environment, true)
    if (online.ok) return online
    if ("reason" in online && online.reason !== "Transaction verification failed") {
      return {
        ok: false,
        reason: online.reason,
        clientCode: mapVerifyFailureClientCode(online.reason),
      }
    }
    if ("retryWithoutOnlineChecks" in online) {
      const offline = await verifyDecodedAppleTransaction(jws, environment, false)
      if (offline.ok) return offline
      if ("reason" in offline && offline.reason !== "Transaction verification failed") {
        return {
          ok: false,
          reason: offline.reason,
          clientCode: mapVerifyFailureClientCode(offline.reason),
        }
      }
    }
  }

  return {
    ok: false,
    reason: "Transaction verification failed",
    clientCode: "VERIFICATION_FAILED",
  }
}

function mapVerifyFailureClientCode(
  reason: string
): NonNullable<Extract<AppleSignedTransactionVerifyResult, { ok: false }>["clientCode"]> {
  if (reason === "Unknown TraxPro product") return "UNKNOWN_PRODUCT"
  if (reason === "Apple verification is not configured") return "APPLE_NOT_CONFIGURED"
  if (reason === STOREKIT_TESTING_NOT_VERIFIABLE_REASON) {
    return "STOREKIT_TESTING_NOT_VERIFIABLE"
  }
  if (reason === "Transaction bundle ID does not match server configuration") {
    return "APPLE_BUNDLE_MISMATCH"
  }
  return "VERIFICATION_FAILED"
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
    const verifier = createVerifier(environment, true)
    if (!verifier) continue

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
    const verifier = createVerifier(environment, true)
    if (!verifier) continue

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

  if (!appleAppAccountTokenMatchesUser(transaction.appAccountToken, userId)) {
    return {
      ok: false,
      reason: "This App Store purchase is linked to a different TradeTraxs account",
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
