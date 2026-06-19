import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { BETA_REFERRAL_CODE } from "@/lib/betaReferralCode"
import { SITE_URL } from "@/lib/site"
import { sendBetaSignupAdminEmail } from "@/lib/server/sendBetaSignupAdminEmail"

function normalizeReferralCode(value: string | null | undefined): string {
  return value != null ? String(value).trim().toUpperCase() : ""
}

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let signupMethod: string | null = null
  try {
    const body = (await req.json()) as { signupMethod?: string }
    signupMethod = body.signupMethod?.trim() || null
  } catch {
    // Optional body — signup method is nice-to-have only.
  }

  const { data: profile, error: profileErr } = await supabaseServiceRole
    .from("profiles")
    .select(
      "id, username, name, referred_by, is_beta_tester, is_pro, created_at, beta_signup_notified_at"
    )
    .eq("id", user.id)
    .maybeSingle()

  if (profileErr || !profile) {
    console.error("[admin-notify/beta-signup] profile load failed", profileErr)
    return Response.json({ error: "Profile not found" }, { status: 404 })
  }

  if (profile.is_beta_tester !== true) {
    return Response.json({ error: "Not a beta tester" }, { status: 400 })
  }

  if (normalizeReferralCode(profile.referred_by) !== BETA_REFERRAL_CODE) {
    return Response.json({ error: "Not a beta referral signup" }, { status: 400 })
  }

  if (profile.beta_signup_notified_at) {
    return Response.json({ ok: true, alreadyNotified: true })
  }

  const claimedAt = new Date().toISOString()
  const { data: claimed, error: claimErr } = await supabaseServiceRole
    .from("profiles")
    .update({ beta_signup_notified_at: claimedAt })
    .eq("id", user.id)
    .is("beta_signup_notified_at", null)
    .select(
      "id, username, name, referred_by, is_beta_tester, is_pro, created_at"
    )
    .maybeSingle()

  if (claimErr) {
    console.error("[admin-notify/beta-signup] claim failed", claimErr)
    return Response.json({ error: "Could not claim notification slot" }, { status: 500 })
  }

  if (!claimed) {
    return Response.json({ ok: true, alreadyNotified: true })
  }

  const emailResult = await sendBetaSignupAdminEmail({
    userId: user.id,
    userEmail: user.email ?? null,
    username: claimed.username != null ? String(claimed.username) : null,
    displayName: claimed.name != null ? String(claimed.name) : null,
    referredBy: claimed.referred_by != null ? String(claimed.referred_by) : null,
    isBetaTester: claimed.is_beta_tester === true,
    isPro: claimed.is_pro === true,
    createdAt: claimed.created_at != null ? String(claimed.created_at) : null,
    signupMethod,
    adminUrl: `${SITE_URL}/admin/users`,
  })

  if (!emailResult.ok && !emailResult.skipped) {
    console.error("[admin-notify/beta-signup] email failed", {
      userId: user.id,
      error: emailResult.error,
    })
    const { error: revertErr } = await supabaseServiceRole
      .from("profiles")
      .update({ beta_signup_notified_at: null })
      .eq("id", user.id)
      .eq("beta_signup_notified_at", claimedAt)

    if (revertErr) {
      console.error("[admin-notify/beta-signup] revert claim failed", revertErr)
    }
  }

  return Response.json({ ok: true, emailSent: emailResult.ok })
}
