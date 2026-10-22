import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isProActive } from "@/lib/subscription"

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { data: profile, error } = await supabaseServiceRole
    .from("profiles")
    .select(
      "use_free_tier, is_pro, creator_access, subscription_status, trial_end, early_access_enrolled_at, early_access_started_at, early_access_status, early_access_ends_at, early_access_campaign_id, early_access_enrollment_source"
    )
    .eq("id", user.id)
    .maybeSingle()

  if (error || !profile) {
    return Response.json({ error: "Profile not found" }, { status: 404 })
  }

  if (profile.use_free_tier === true) {
    return Response.json({ ok: true, applied: false })
  }

  if (isProActive(profile)) {
    return Response.json({ ok: true, applied: false })
  }

  const { error: updateErr } = await supabaseServiceRole
    .from("profiles")
    .update({ use_free_tier: true })
    .eq("id", user.id)

  if (updateErr) {
    console.error("[api/profile/mark-free-tier]", updateErr)
    return Response.json({ error: "Could not mark free tier" }, { status: 500 })
  }

  return Response.json({ ok: true, applied: true })
}
