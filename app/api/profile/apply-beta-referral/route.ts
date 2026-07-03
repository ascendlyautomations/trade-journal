import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { BETA_REFERRAL_CODE, isBetaReferralRef } from "@/lib/betaReferralCode"

const BETA_REFERRAL_WINDOW_MS = 7 * 24 * 60 * 60 * 1000

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: { code?: string }
  try {
    body = (await req.json()) as typeof body
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const code = body.code?.trim() ?? ""
  if (!isBetaReferralRef(code)) {
    return Response.json({ error: "Invalid beta referral code" }, { status: 400 })
  }

  const { data: profile, error } = await supabaseServiceRole
    .from("profiles")
    .select("referred_by, is_beta_tester, created_at")
    .eq("id", user.id)
    .maybeSingle()

  if (error || !profile) {
    return Response.json({ error: "Profile not found" }, { status: 404 })
  }

  if (profile.is_beta_tester === true) {
    return Response.json({ ok: true, applied: false, reason: "already_beta" })
  }

  const referredBy =
    profile.referred_by != null ? String(profile.referred_by).trim() : ""
  if (referredBy) {
    return Response.json({ ok: true, applied: false, reason: "referral_set" })
  }

  const createdAt = profile.created_at
    ? new Date(String(profile.created_at)).getTime()
    : NaN
  if (
    Number.isNaN(createdAt) ||
    Date.now() - createdAt > BETA_REFERRAL_WINDOW_MS
  ) {
    return Response.json({ error: "Beta referral window expired" }, { status: 403 })
  }

  const { error: updateErr } = await supabaseServiceRole
    .from("profiles")
    .update({ referred_by: BETA_REFERRAL_CODE })
    .eq("id", user.id)

  if (updateErr) {
    console.error("[api/profile/apply-beta-referral]", updateErr)
    return Response.json({ error: "Could not apply beta referral" }, { status: 500 })
  }

  return Response.json({ ok: true, applied: true })
}
