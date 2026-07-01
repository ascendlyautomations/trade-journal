import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  createAffiliateReferralNotification,
  resolveAffiliateUserIdFromCode,
} from "@/lib/server/affiliateReferralNotifications"

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { data: profile, error: profileErr } = await supabaseServiceRole
    .from("profiles")
    .select("referred_by")
    .eq("id", user.id)
    .maybeSingle()

  if (profileErr) {
    console.error("[api/notifications/affiliate-referral] profile lookup failed", profileErr)
    return Response.json({ error: profileErr.message }, { status: 500 })
  }

  const referredBy =
    profile?.referred_by != null ? String(profile.referred_by).trim() : ""
  if (!referredBy) {
    return Response.json({ ok: true, skipped: true })
  }

  const affiliateUserId = await resolveAffiliateUserIdFromCode(
    supabaseServiceRole,
    referredBy
  )
  if (!affiliateUserId || affiliateUserId === user.id) {
    return Response.json({ ok: true, skipped: true })
  }

  await createAffiliateReferralNotification(supabaseServiceRole, {
    affiliateUserId,
    referredUserId: user.id,
  })

  return Response.json({ ok: true })
}
