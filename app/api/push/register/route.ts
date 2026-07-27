import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

type RegisterBody = {
  deviceToken?: string
  platform?: string
  appVersion?: string | null
}

/**
 * Upsert an iOS APNs device token for the authenticated user.
 * Reassigns the token if it was previously tied to another account.
 * Single DB round-trip (upsert on device_token).
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

  const now = new Date().toISOString()

  const { error } = await supabaseServiceRole.from("device_push_tokens").upsert(
    {
      user_id: user.id,
      platform: "ios",
      device_token: deviceToken,
      app_version: appVersion,
      updated_at: now,
      last_seen_at: now,
    },
    { onConflict: "device_token" }
  )

  if (error) {
    console.error("[api/push/register] upsert failed", error)
    return Response.json({ error: error.message }, { status: 500 })
  }

  return Response.json({ ok: true })
}
