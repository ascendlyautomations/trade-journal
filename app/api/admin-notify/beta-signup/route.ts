import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { SITE_URL } from "@/lib/site"
import { sendBetaSignupAdminEmail } from "@/lib/server/sendBetaSignupAdminEmail"
import { devLog } from "@/lib/devLog"

export async function POST(req: Request) {
  devLog("[beta-signup-email] route hit")

  const user = await getRouteUser(req)
  if (!user) {
    devLog("[beta-signup-email] skipped reason: unauthorized")
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  devLog("[beta-signup-email] user id", user.id)

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

  devLog("[beta-signup-email] profile fields", {
    userId: user.id,
    onboarding_completed: profile.onboarding_completed,
    beta_signup_notified_at: profile.beta_signup_notified_at,
    signupMethod,
  })

  if (profile.beta_signup_notified_at) {
    devLog("[beta-signup-email] skipped reason: already_notified", {
      userId: user.id,
      beta_signup_notified_at: profile.beta_signup_notified_at,
    })
    return Response.json({ ok: true, alreadyNotified: true })
  }

  const username = profile.username != null ? String(profile.username).trim() : ""
  const profileCompletedAt = new Date().toISOString()

  const emailResult = await sendBetaSignupAdminEmail({
    userId: user.id,
    userEmail: user.email ?? null,
    username: username || null,
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
      devLog("[beta-signup-email] skipped reason: resend_not_configured", {
        userId: user.id,
      })
    }
    return Response.json({ ok: true, emailSent: false })
  }

  devLog("[beta-signup-email] sent email id", {
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
