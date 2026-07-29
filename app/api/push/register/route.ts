import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { getApnsRuntimeInfo } from "@/lib/server/push/apns"

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
  const apns = getApnsRuntimeInfo()

  // TEMPORARY [tt-push-debug]
  console.info("[tt-push-debug] register upsert", {
    userId: user.id,
    platform,
    deviceToken,
    apnsEnvironment: apns.production ? "production" : "sandbox",
    bundleId: apns.bundleId,
    timestamp: now,
  })

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

  // TEMPORARY [tt-push-debug] — read back to prove DB matches phone token.
  const { data: storedRows, error: readErr } = await supabaseServiceRole
    .from("device_push_tokens")
    .select("device_token, user_id, platform, updated_at")
    .eq("user_id", user.id)
    .eq("platform", "ios")

  if (readErr) {
    console.error("[tt-push-debug] register read-back failed", readErr)
  }

  const tokens = (storedRows ?? []).map((row) =>
    String(row.device_token ?? "").trim()
  )
  const tokenMatchesStored = tokens.includes(deviceToken)

  console.info("[tt-push-debug] register stored tokens for user", {
    userId: user.id,
    phoneToken: deviceToken,
    storedTokens: tokens,
    tokenMatchesStored,
    apnsEnvironment: apns.production ? "production" : "sandbox",
  })

  return Response.json({
    ok: true,
    // TEMPORARY [tt-push-debug] — remove after diagnosis.
    debug: {
      userId: user.id,
      platform: "ios",
      deviceToken,
      storedDeviceToken: tokens.find((t) => t === deviceToken) ?? tokens[0] ?? null,
      storedTokens: tokens,
      tokenMatchesStored,
      apnsEnvironment: apns.production ? "production" : "sandbox",
      bundleId: apns.bundleId,
    },
  })
}
