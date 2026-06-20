import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { BETA_REFERRAL_CODE } from "@/lib/betaReferralCode"
import { SITE_URL } from "@/lib/site"
import { sendBetaSignupAdminEmail } from "@/lib/server/sendBetaSignupAdminEmail"

function normalizeReferralCode(value: string | null | undefined): string {
  return value != null ? String(value).trim().toUpperCase() : ""
}

function isBetaSignupEligible(profile: {
  is_beta_tester?: boolean | null
  referred_by?: string | null
}): boolean {
  if (profile.is_beta_tester === true) return true
  return normalizeReferralCode(profile.referred_by) === BETA_REFERRAL_CODE
}

export async function POST(req: Request) {
  console.log("[beta-signup-email] route hit")

  const user = await getRouteUser(req)
  if (!user) {
    console.log("[beta-signup-email] skipped reason: unauthorized")
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  console.log("[beta-signup-email] user id", user.id)

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
      "id, username, name, referred_by, is_beta_tester, is_pro, created_at, onboarding_completed, beta_signup_notified_at"
    )
    .eq("id", user.id)
    .maybeSingle()

  if (profileErr || !profile) {
    console.error("[beta-signup-email] skipped reason: profile_load_failed", profileErr)
    return Response.json({ error: "Profile not found" }, { status: 404 })
  }

  console.log("[beta-signup-email] profile beta fields", {
    userId: user.id,
    referred_by: profile.referred_by,
    is_beta_tester: profile.is_beta_tester,
    is_pro: profile.is_pro,
    beta_signup_notified_at: profile.beta_signup_notified_at,
    signupMethod,
  })

  if (profile.beta_signup_notified_at) {
    console.log("[beta-signup-email] skipped reason: already_notified", {
      userId: user.id,
      beta_signup_notified_at: profile.beta_signup_notified_at,
    })
    return Response.json({ ok: true, alreadyNotified: true })
  }

  if (!isBetaSignupEligible(profile)) {
    console.log("[beta-signup-email] skipped reason: not_eligible", {
      userId: user.id,
      referred_by: profile.referred_by,
      is_beta_tester: profile.is_beta_tester,
    })
    return Response.json({ ok: true, skipped: true, reason: "not_eligible" })
  }

  const username = profile.username != null ? String(profile.username).trim() : ""
  if (!username) {
    console.log("[beta-signup-email] skipped reason: username_missing", {
      userId: user.id,
    })
    return Response.json({ ok: true, skipped: true, reason: "username_missing" })
  }

  if (profile.onboarding_completed !== true) {
    console.log("[beta-signup-email] skipped reason: onboarding_incomplete", {
      userId: user.id,
    })
    return Response.json({ ok: true, skipped: true, reason: "onboarding_incomplete" })
  }

  const profileCompletedAt = new Date().toISOString()

  const emailResult = await sendBetaSignupAdminEmail({
    userId: user.id,
    userEmail: user.email ?? null,
    username,
    name: profile.name != null ? String(profile.name).trim() || null : null,
    displayName: profile.name != null ? String(profile.name).trim() || null : null,
    referredBy: profile.referred_by != null ? String(profile.referred_by) : null,
    isBetaTester: profile.is_beta_tester === true,
    isPro: profile.is_pro === true,
    createdAt: profile.created_at != null ? String(profile.created_at) : null,
    profileCompletedAt,
    signupMethod,
    adminUrl: `${SITE_URL}/admin/users`,
  })

  if (!emailResult.ok) {
    if (!emailResult.skipped) {
      console.error("[beta-signup-email] resend error", {
        userId: user.id,
        error: emailResult.error,
      })
    } else {
      console.log("[beta-signup-email] skipped reason: resend_not_configured", {
        userId: user.id,
      })
    }
    return Response.json({ ok: true, emailSent: false })
  }

  console.log("[beta-signup-email] sent email id", {
    userId: user.id,
    emailId: emailResult.emailId,
  })

  const notifiedAt = new Date().toISOString()
  const { error: markErr } = await supabaseServiceRole
    .from("profiles")
    .update({ beta_signup_notified_at: notifiedAt })
    .eq("id", user.id)
    .is("beta_signup_notified_at", null)

  if (markErr) {
    console.error("[beta-signup-email] failed to set beta_signup_notified_at", {
      userId: user.id,
      error: markErr,
    })
  }

  return Response.json({ ok: true, emailSent: true, emailId: emailResult.emailId })
}
