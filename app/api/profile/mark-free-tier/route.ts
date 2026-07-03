import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

const FREE_TIER_WINDOW_MS = 7 * 24 * 60 * 60 * 1000

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { data: profile, error } = await supabaseServiceRole
    .from("profiles")
    .select("use_free_tier, is_pro, subscription_status, trial_end, created_at")
    .eq("id", user.id)
    .maybeSingle()

  if (error || !profile) {
    return Response.json({ error: "Profile not found" }, { status: 404 })
  }

  if (profile.use_free_tier === true) {
    return Response.json({ ok: true, applied: false })
  }

  const createdAt = profile.created_at
    ? new Date(String(profile.created_at)).getTime()
    : NaN
  if (
    Number.isNaN(createdAt) ||
    Date.now() - createdAt > FREE_TIER_WINDOW_MS
  ) {
    return Response.json({ error: "Free tier signup window expired" }, { status: 403 })
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
