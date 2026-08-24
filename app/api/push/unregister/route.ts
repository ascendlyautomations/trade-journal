import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

type UnregisterBody = {
  deviceToken?: string
  /** When true, remove every token for this user (full sign-out). */
  allDevices?: boolean
}

/**
 * Remove a device token (or all tokens for the authenticated user).
 *
 * Authenticated: scoped to the current user (or allDevices).
 * Unauthenticated: allows delete by opaque device token alone so logout can
 * unregister after a session race — possession of the APNs token is the authz.
 */
export async function POST(req: Request) {
  let body: UnregisterBody = {}
  try {
    body = (await req.json()) as UnregisterBody
  } catch {
    body = {}
  }

  const deviceToken = body.deviceToken?.trim()
  const allDevices = body.allDevices === true
  const user = await getRouteUser(req)

  if (!user) {
    if (!deviceToken || deviceToken.length < 16) {
      return Response.json({ error: "Unauthorized" }, { status: 401 })
    }
    const { error } = await supabaseServiceRole
      .from("device_push_tokens")
      .delete()
      .eq("device_token", deviceToken)
    if (error) {
      console.error("[api/push/unregister] anonymous token delete failed", error)
      return Response.json({ error: error.message }, { status: 500 })
    }
    return Response.json({ ok: true })
  }

  if (!allDevices && !deviceToken) {
    return Response.json(
      { error: "deviceToken or allDevices required" },
      { status: 400 }
    )
  }

  let query = supabaseServiceRole
    .from("device_push_tokens")
    .delete()
    .eq("user_id", user.id)

  if (!allDevices && deviceToken) {
    query = query.eq("device_token", deviceToken)
  }

  const { error } = await query
  if (error) {
    console.error("[api/push/unregister] delete failed", error)
    return Response.json({ error: error.message }, { status: 500 })
  }

  return Response.json({ ok: true })
}
