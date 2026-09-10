import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  assertAppleTransactionNotBoundToOtherUser,
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

  if (!signedTransactionInfo && !transactionId) {
    return Response.json(
      { error: "Missing transactionId or signedTransactionInfo" },
      { status: 400 }
    )
  }

  const verified = signedTransactionInfo
    ? await verifyAppleSignedTransactionInfo(signedTransactionInfo)
    : await verifyAppleTransactionId(transactionId!)
  if (!verified.ok) {
    return Response.json({ error: verified.reason }, { status: 400 })
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
