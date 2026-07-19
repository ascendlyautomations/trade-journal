import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  backfillReferredByIfMissing,
  createSupabaseReferralAttributionDb,
} from "@/lib/referralAttribution"

/**
 * Set-once backfill of the caller's own `referred_by`.
 *
 * `referred_by` is protected from authenticated self-updates by DB triggers,
 * so when an auth trigger creates the profile shell before the signup insert,
 * the referral attribution is lost. This route restores it with the service
 * role, but ONLY when `referred_by` is currently NULL — existing referral
 * relationships can never be overwritten or edited through this endpoint.
 */
export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const body = (await req.json().catch(() => null)) as {
    code?: unknown
  } | null

  // Prefer the client-persisted code; fall back to the referral code stamped
  // into auth metadata at email signup.
  const candidate = body?.code ?? user.user_metadata?.referral_code

  const result = await backfillReferredByIfMissing(
    createSupabaseReferralAttributionDb(supabaseServiceRole),
    user.id,
    candidate
  )

  if (result === "error") {
    console.error("[referral-attribution] backfill failed", {
      userId: user.id,
    })
    return Response.json(
      { error: "Could not record referral attribution." },
      { status: 500 }
    )
  }

  return Response.json({ result })
}
