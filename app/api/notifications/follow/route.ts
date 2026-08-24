import { getRouteUser } from "@/app/api/_lib/getRouteUser"
import { notify } from "@/lib/server/notifications/NotificationService"

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

  const result = await notify({
    type: "follow",
    actorUserId: user.id,
    followingId: followingId ?? "",
  })

  if (!result.ok) {
    return Response.json(
      { error: result.error ?? "Follow notify failed" },
      { status: result.status ?? 500 }
    )
  }

  return Response.json({
    ok: true,
    deduplicated: result.deduplicated,
  })
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

  const { supabaseServiceRole } = await import("@/app/api/_lib/getRouteUser")
  const { invalidateAppIconBadgeCache } = await import(
    "@/lib/server/push/badgeService"
  )
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

  invalidateAppIconBadgeCache(followingId)
  return Response.json({ ok: true })
}
