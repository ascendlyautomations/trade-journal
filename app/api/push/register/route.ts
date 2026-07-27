import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

type RegisterBody = {
  deviceToken?: string
  platform?: string
  appVersion?: string | null
}

/** TEMPORARY diagnostics — never log full device tokens. Remove after verification. */
function maskDeviceToken(token: string): string {
  const t = token.trim()
  if (t.length < 14) return "***"
  return `${t.slice(0, 8)}...${t.slice(-6)}`
}

/**
 * Upsert an iOS APNs device token for the authenticated user.
 * Reassigns the token if it was previously tied to another account.
 */
export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: RegisterBody
  try {
    body = (await req.json()) as RegisterBody
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const deviceToken = body.deviceToken?.trim()
  const platform = body.platform?.trim().toLowerCase() || "ios"
  const appVersion =
    typeof body.appVersion === "string" ? body.appVersion.trim() || null : null

  if (!deviceToken || deviceToken.length < 16) {
    return Response.json({ error: "Invalid deviceToken" }, { status: 400 })
  }
  if (platform !== "ios") {
    return Response.json({ error: "Unsupported platform" }, { status: 400 })
  }

  const tokenPreview = maskDeviceToken(deviceToken)
  // TEMPORARY diagnostics
  console.info("[api/push/register:temp] upsert start", {
    tokenPreview,
    userIdPrefix: user.id.slice(0, 8),
  })

  const now = new Date().toISOString()

  const { data: existing, error: lookupErr } = await supabaseServiceRole
    .from("device_push_tokens")
    .select("id, user_id")
    .eq("device_token", deviceToken)
    .maybeSingle()

  if (lookupErr) {
    console.error("[api/push/register] lookup failed", lookupErr)
    console.error("[api/push/register:temp] lookup failed", {
      tokenPreview,
      message: lookupErr.message,
    })
    return Response.json({ error: lookupErr.message }, { status: 500 })
  }

  if (existing?.id) {
    const { error: updateErr } = await supabaseServiceRole
      .from("device_push_tokens")
      .update({
        user_id: user.id,
        platform: "ios",
        app_version: appVersion,
        updated_at: now,
        last_seen_at: now,
      })
      .eq("id", existing.id)

    if (updateErr) {
      console.error("[api/push/register] update failed", updateErr)
      console.error("[api/push/register:temp] update failed", {
        tokenPreview,
        message: updateErr.message,
      })
      return Response.json({ error: updateErr.message }, { status: 500 })
    }
    // TEMPORARY diagnostics
    console.info("[api/push/register:temp] update success", { tokenPreview })
    return Response.json({ ok: true, updated: true })
  }

  const { error: insertErr } = await supabaseServiceRole
    .from("device_push_tokens")
    .insert({
      user_id: user.id,
      platform: "ios",
      device_token: deviceToken,
      app_version: appVersion,
      created_at: now,
      updated_at: now,
      last_seen_at: now,
    })

  if (insertErr) {
    if (insertErr.code === "23505") {
      // Race: another request inserted the same token — retry as update.
      const { error: raceErr } = await supabaseServiceRole
        .from("device_push_tokens")
        .update({
          user_id: user.id,
          platform: "ios",
          app_version: appVersion,
          updated_at: now,
          last_seen_at: now,
        })
        .eq("device_token", deviceToken)
      if (raceErr) {
        console.error("[api/push/register] race update failed", raceErr)
        console.error("[api/push/register:temp] race update failed", {
          tokenPreview,
          message: raceErr.message,
        })
        return Response.json({ error: raceErr.message }, { status: 500 })
      }
      // TEMPORARY diagnostics
      console.info("[api/push/register:temp] race update success", {
        tokenPreview,
      })
      return Response.json({ ok: true, updated: true })
    }
    console.error("[api/push/register] insert failed", insertErr)
    console.error("[api/push/register:temp] insert failed", {
      tokenPreview,
      message: insertErr.message,
    })
    return Response.json({ error: insertErr.message }, { status: 500 })
  }

  // TEMPORARY diagnostics
  console.info("[api/push/register:temp] insert success", { tokenPreview })
  return Response.json({ ok: true, created: true })
}
