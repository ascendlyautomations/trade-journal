import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

type RegisterBody = {
  deviceToken?: string
  /** Prior APNs token from this install (local cache) when the token rotated. */
  previousDeviceToken?: string | null
  /**
   * Stable install identity (iOS identifierForVendor via Capacitor Device.getId).
   * Same install → one row; token rotations update device_token in place.
   * Different devices → different ids → multiple rows per user preserved.
   */
  installationId?: string | null
  platform?: string
  appVersion?: string | null
}

/**
 * Register / refresh an iOS APNs device token for the authenticated user.
 *
 * Apple recommends sending the current token on every launch. Tokens can change
 * on reinstall / restore / OS update. This endpoint:
 * - Upserts by installation_id when provided (replaces rotated tokens in place)
 * - Deletes previousDeviceToken when it differs from the new token
 * - Reassigns a token if it was tied to another account
 * - Preserves other devices' rows for the same user
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
  const previousDeviceToken =
    typeof body.previousDeviceToken === "string"
      ? body.previousDeviceToken.trim() || null
      : null
  const installationId =
    typeof body.installationId === "string"
      ? body.installationId.trim() || null
      : null
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
  const db = supabaseServiceRole

  // Drop the prior token for this install when APNs issued a new one.
  if (
    previousDeviceToken &&
    previousDeviceToken !== deviceToken &&
    previousDeviceToken.length >= 16
  ) {
    const { error: prevErr } = await db
      .from("device_push_tokens")
      .delete()
      .eq("device_token", previousDeviceToken)
    if (prevErr) {
      console.error("[api/push/register] previous token delete failed", prevErr)
      return Response.json({ error: prevErr.message }, { status: 500 })
    }
  }

  if (installationId) {
    // Token may already exist under a different installation row (rare) —
    // remove that row so the unique(device_token) constraint allows the update.
    const { data: tokenRow, error: tokenLookupErr } = await db
      .from("device_push_tokens")
      .select("id, installation_id")
      .eq("device_token", deviceToken)
      .maybeSingle()

    if (tokenLookupErr) {
      console.error("[api/push/register] token lookup failed", tokenLookupErr)
      return Response.json({ error: tokenLookupErr.message }, { status: 500 })
    }

    if (
      tokenRow &&
      tokenRow.installation_id &&
      tokenRow.installation_id !== installationId
    ) {
      const { error: conflictErr } = await db
        .from("device_push_tokens")
        .delete()
        .eq("id", tokenRow.id)
      if (conflictErr) {
        console.error(
          "[api/push/register] conflicting token row delete failed",
          conflictErr
        )
        return Response.json({ error: conflictErr.message }, { status: 500 })
      }
    }

    const { data: installRow, error: installLookupErr } = await db
      .from("device_push_tokens")
      .select("id, device_token")
      .eq("installation_id", installationId)
      .maybeSingle()

    if (installLookupErr) {
      console.error(
        "[api/push/register] installation lookup failed",
        installLookupErr
      )
      return Response.json({ error: installLookupErr.message }, { status: 500 })
    }

    if (installRow) {
      // Same install: update token / user in place (rotation or re-login).
      if (installRow.device_token !== deviceToken) {
        const { error: staleTokenErr } = await db
          .from("device_push_tokens")
          .delete()
          .eq("device_token", deviceToken)
          .neq("id", installRow.id)
        if (staleTokenErr) {
          console.error(
            "[api/push/register] stale token cleanup failed",
            staleTokenErr
          )
          return Response.json(
            { error: staleTokenErr.message },
            { status: 500 }
          )
        }
      }

      const { error: updateErr } = await db
        .from("device_push_tokens")
        .update({
          user_id: user.id,
          platform: "ios",
          device_token: deviceToken,
          app_version: appVersion,
          updated_at: now,
          last_seen_at: now,
        })
        .eq("id", installRow.id)

      if (updateErr) {
        console.error("[api/push/register] installation update failed", updateErr)
        return Response.json({ error: updateErr.message }, { status: 500 })
      }
    } else if (tokenRow) {
      // Existing token row without this installation_id (legacy) — attach id.
      const { error: attachErr } = await db
        .from("device_push_tokens")
        .update({
          user_id: user.id,
          installation_id: installationId,
          app_version: appVersion,
          updated_at: now,
          last_seen_at: now,
        })
        .eq("id", tokenRow.id)

      if (attachErr) {
        console.error(
          "[api/push/register] attach installation_id failed",
          attachErr
        )
        return Response.json({ error: attachErr.message }, { status: 500 })
      }
    } else {
      const { error: insertErr } = await db.from("device_push_tokens").insert({
        user_id: user.id,
        platform: "ios",
        device_token: deviceToken,
        installation_id: installationId,
        app_version: appVersion,
        updated_at: now,
        last_seen_at: now,
      })

      if (insertErr) {
        console.error("[api/push/register] insert failed", insertErr)
        return Response.json({ error: insertErr.message }, { status: 500 })
      }
    }
  } else {
    // Legacy clients without installationId — upsert on device_token only.
    const { error } = await db.from("device_push_tokens").upsert(
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
  }

  return Response.json({
    ok: true,
    deviceToken,
    installationId,
    rotated:
      Boolean(previousDeviceToken) && previousDeviceToken !== deviceToken,
  })
}
