import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

type UnregisterBody = {
  deviceToken?: string
  /** When true, remove every token for this user (full sign-out). */
  allDevices?: boolean
}

/** Remove the current device token (or all tokens) for the authenticated user. */
export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: UnregisterBody = {}
  try {
    body = (await req.json()) as UnregisterBody
  } catch {
    // Empty body is fine when allDevices is intended via query — still require JSON or empty.
    body = {}
  }

  const deviceToken = body.deviceToken?.trim()
  const allDevices = body.allDevices === true

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
