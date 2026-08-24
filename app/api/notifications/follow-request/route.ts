import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { notify } from "@/lib/server/notifications/NotificationService"

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let targetId: string | undefined
  try {
    const body = (await req.json()) as { targetId?: string }
    targetId = body.targetId?.trim()
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const result = await notify({
    type: "follow_request",
    actorUserId: user.id,
    targetId: targetId ?? "",
  })

  if (!result.ok) {
    return Response.json(
      { error: result.error ?? "Follow request notify failed" },
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

  let targetId: string | undefined
  try {
    const body = (await req.json()) as { targetId?: string }
    targetId = body.targetId?.trim()
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  if (!targetId || targetId === user.id) {
    return Response.json({ error: "Invalid targetId" }, { status: 400 })
  }

  const { error: deleteErr } = await supabaseServiceRole
    .from("notifications")
    .delete()
    .eq("user_id", targetId)
    .eq("sender_id", user.id)
    .eq("type", "follow_request")

  if (deleteErr) {
    console.error("[api/notifications/follow-request] delete failed", deleteErr)
    return Response.json({ error: deleteErr.message }, { status: 500 })
  }

  const { invalidateAppIconBadgeCache } = await import(
    "@/lib/server/push/badgeService"
  )
  invalidateAppIconBadgeCache(targetId)
  return Response.json({ ok: true })
}
