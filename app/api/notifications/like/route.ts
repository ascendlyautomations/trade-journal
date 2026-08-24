import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { notify } from "@/lib/server/notifications/NotificationService"
import {
  resolveLikeTarget,
  type LikeTarget,
} from "@/lib/server/notifications/handlers/likeNotify"

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) return Response.json({ error: "Unauthorized" }, { status: 401 })

  let target: LikeTarget
  try {
    target = ((await req.json()) as { target?: LikeTarget }).target as LikeTarget
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  if (!target) {
    return Response.json({ error: "Invalid target" }, { status: 400 })
  }

  const result = await notify({
    type: "like",
    actorUserId: user.id,
    target,
  })

  if (!result.ok) {
    return Response.json(
      { error: result.error ?? "Like notify failed" },
      { status: result.status ?? 500 }
    )
  }

  return Response.json({
    ok: true,
    skipped: result.skipped,
    deduplicated: result.deduplicated,
  })
}

export async function DELETE(req: Request) {
  const user = await getRouteUser(req)
  if (!user) return Response.json({ error: "Unauthorized" }, { status: 401 })

  let target: LikeTarget
  try {
    target = ((await req.json()) as { target?: LikeTarget }).target as LikeTarget
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const resolved = target ? await resolveLikeTarget(target, user.id) : null
  if (!resolved) {
    return Response.json({ error: "Target not found" }, { status: 404 })
  }

  let query = supabaseServiceRole
    .from("notifications")
    .delete()
    .eq("type", "like")
    .eq("user_id", resolved.recipientUserId)
    .eq("sender_id", user.id)

  for (const [column, value] of Object.entries(resolved.notificationTarget)) {
    if (value) query = query.eq(column, value)
  }

  const { error } = await query
  if (error) {
    console.error("[api/notifications/like] delete failed", error)
    return Response.json({ error: error.message }, { status: 500 })
  }
  const { invalidateAppIconBadgeCache } = await import(
    "@/lib/server/push/badgeService"
  )
  invalidateAppIconBadgeCache(resolved.recipientUserId)
  return Response.json({ ok: true })
}
