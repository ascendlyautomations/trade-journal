import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  assertAppleTransactionNotBoundToOtherUser,
  buildAppleSyncRequestDiagnostics,
  isStoreKitTestingEnvironmentClaim,
  upsertVerifiedAppleSubscription,
  verifyAppleSignedTransactionInfo,
  verifyAppleTransactionId,
} from "@/lib/appleSubscription"
import { buildTraxProEntitlementSnapshot } from "@/lib/traxProEntitlement"

export const runtime = "nodejs"

type SyncBody = {
  /** StoreKit-verified transaction id — server fetches signed info from Apple. */
  transactionId?: string
  /** Optional direct signed JWS when already available. */
  signedTransactionInfo?: string
}

/**
 * Idempotently sync a verified StoreKit 2 transaction to the authenticated user.
 * Client must submit Apple's signed JWS — never client-computed entitlement flags.
 */
export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: SyncBody
  try {
    body = (await req.json()) as SyncBody
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const signedTransactionInfo = body.signedTransactionInfo?.trim()
  const transactionId = body.transactionId?.trim()
  const diagnostics = buildAppleSyncRequestDiagnostics({
    signedTransactionInfo,
    transactionId,
  })

  if (!signedTransactionInfo && !transactionId) {
    return Response.json(
      { error: "Missing transactionId or signedTransactionInfo" },
      { status: 400 }
    )
  }

  let verified = signedTransactionInfo
    ? await verifyAppleSignedTransactionInfo(signedTransactionInfo)
    : null
  const deviceVerificationFailed =
    verified != null &&
    !verified.ok &&
    verified.reason === "Transaction verification failed"
  const storeKitTestingTransaction =
    diagnostics.appearsStoreKitTestingClaim ||
    isStoreKitTestingEnvironmentClaim(diagnostics.claimedEnvironment)

  let transactionIdFallbackAttempted = false
  if (
    (!verified || deviceVerificationFailed) &&
    transactionId &&
    !storeKitTestingTransaction
  ) {
    transactionIdFallbackAttempted = true
    verified = await verifyAppleTransactionId(transactionId)
  }

  if (!verified || !verified.ok) {
    const reason = verified?.reason ?? "Transaction verification failed"
    const clientCode =
      verified && !verified.ok && "clientCode" in verified
        ? verified.clientCode
        : "VERIFICATION_FAILED"

    console.error("[api/apple/subscription/sync] rejected", {
      stage: "sync",
      reason,
      clientCode,
      userId: user.id,
      ...diagnostics,
      transactionIdFallbackAttempted,
      storeKitTestingTransaction,
      jwsVerificationUsed: Boolean(signedTransactionInfo),
      verifierPath: transactionIdFallbackAttempted
        ? "AppStoreServerAPI_getTransactionInfo"
        : "SignedDataVerifier",
    })

    return Response.json(
      {
        error: reason,
        code: clientCode,
      },
      { status: 400 }
    )
  }

  const ownership = await assertAppleTransactionNotBoundToOtherUser(
    supabaseServiceRole,
    verified.transaction.originalTransactionId,
    user.id
  )
  if (!ownership.ok) {
    return Response.json({ error: ownership.reason }, { status: 409 })
  }

  try {
    const appleSubscription = await upsertVerifiedAppleSubscription({
      supabase: supabaseServiceRole,
      userId: user.id,
      transaction: verified.transaction,
    })

    const { data: profile, error: profileErr } = await supabaseServiceRole
      .from("profiles")
      .select(
        "is_pro,creator_access,subscription_status,trial_end,early_access_enrolled_at,early_access_started_at,early_access_status,early_access_ends_at,early_access_campaign_id,early_access_enrollment_source,billing_interval,current_period_end,cancel_at_period_end"
      )
      .eq("id", user.id)
      .single()

    if (profileErr || !profile) {
      return Response.json(
        { error: "Subscription synced but entitlement reload failed" },
        { status: 500 }
      )
    }

    const snapshot = buildTraxProEntitlementSnapshot(profile, appleSubscription)

    return Response.json({
      traxProActive: snapshot.traxProActive,
      source: snapshot.source,
      productId: appleSubscription.product_id,
      billingInterval: snapshot.billingInterval,
      expiresAt: snapshot.appleExpiresAt,
      appleSubscriptionStatus: appleSubscription.status,
    })
  } catch (error) {
    console.error("[api/apple/subscription/sync]", error)
    return Response.json({ error: "Failed to sync subscription" }, { status: 500 })
  }
}
