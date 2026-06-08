import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let followingId: string | undefined
  try {
    const body = (await req.json()) as { followingId?: string }
    followingId = body.followingId?.trim()
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  if (!followingId || followingId === user.id) {
    return Response.json({ error: "Invalid followingId" }, { status: 400 })
  }

  const { data: followRow, error: followErr } = await supabaseServiceRole
    .from("followers")
    .select("follower_id")
    .eq("follower_id", user.id)
    .eq("following_id", followingId)
    .maybeSingle()

  if (followErr) {
    console.error("[api/notifications/follow] follow lookup failed", followErr)
    return Response.json({ error: followErr.message }, { status: 500 })
  }

  if (!followRow) {
    return Response.json(
      { error: "Follow relationship not found" },
      { status: 404 }
    )
  }

  const { error: insertErr } = await supabaseServiceRole
    .from("notifications")
    .insert({
      user_id: followingId,
      sender_id: user.id,
      type: "follow",
    })

  if (insertErr) {
    console.error("[api/notifications/follow] insert failed", insertErr)
    return Response.json({ error: insertErr.message }, { status: 500 })
  }

  return Response.json({ ok: true })
}

export async function DELETE(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let followingId: string | undefined
  try {
    const body = (await req.json()) as { followingId?: string }
    followingId = body.followingId?.trim()
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  if (!followingId || followingId === user.id) {
    return Response.json({ error: "Invalid followingId" }, { status: 400 })
  }

  const { error: deleteErr } = await supabaseServiceRole
    .from("notifications")
    .delete()
    .eq("user_id", followingId)
    .eq("sender_id", user.id)
    .eq("type", "follow")

  if (deleteErr) {
    console.error("[api/notifications/follow] delete failed", deleteErr)
    return Response.json({ error: deleteErr.message }, { status: 500 })
  }

  return Response.json({ ok: true })
}
