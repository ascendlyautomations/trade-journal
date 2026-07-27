import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

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

  if (!targetId || targetId === user.id) {
    return Response.json({ error: "Invalid targetId" }, { status: 400 })
  }

  const { data: requestRow, error: requestErr } = await supabaseServiceRole
    .from("follow_requests")
    .select("id")
    .eq("requester_id", user.id)
    .eq("target_id", targetId)
    .eq("status", "pending")
    .maybeSingle()

  if (requestErr) {
    console.error("[api/notifications/follow-request] lookup failed", requestErr)
    return Response.json({ error: requestErr.message }, { status: 500 })
  }

  if (!requestRow) {
    return Response.json(
      { error: "Pending follow request not found" },
      { status: 404 }
    )
  }

  const { error: insertErr } = await supabaseServiceRole
    .from("notifications")
    .insert({
      user_id: targetId,
      sender_id: user.id,
      type: "follow_request",
      content: JSON.stringify({ follow_request_id: requestRow.id }),
    })

  if (insertErr) {
    if (insertErr.code === "23505") {
      return Response.json({ ok: true, deduplicated: true })
    }
    console.error("[api/notifications/follow-request] insert failed", insertErr)
    return Response.json({ error: insertErr.message }, { status: 500 })
  }

  const { scheduleIosPushDelivery } = await import(
    "@/lib/server/push/deliverPushNotification"
  )
  scheduleIosPushDelivery({
    recipientUserId: targetId,
    type: "follow_request",
    sender_id: user.id,
    content: JSON.stringify({ follow_request_id: requestRow.id }),
    prefsAlreadyChecked: true,
  })

  return Response.json({ ok: true })
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

  return Response.json({ ok: true })
}
