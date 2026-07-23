import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let roomId: string | undefined
  try {
    const body = (await req.json()) as { roomId?: string }
    roomId = body.roomId?.trim()
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  if (!roomId) {
    return Response.json({ error: "Invalid roomId" }, { status: 400 })
  }

  const { data: memberRow, error: memberErr } = await supabaseServiceRole
    .from("room_members")
    .select("id")
    .eq("room_id", roomId)
    .eq("user_id", user.id)
    .is("left_at", null)
    .maybeSingle()

  if (memberErr) {
    console.error("[api/notifications/room-join] membership lookup failed", memberErr)
    return Response.json({ error: memberErr.message }, { status: 500 })
  }

  if (!memberRow) {
    return Response.json(
      { error: "Active room membership not found" },
      { status: 404 }
    )
  }

  const { data: roomRow, error: roomErr } = await supabaseServiceRole
    .from("rooms")
    .select("owner_user_id, name, slug")
    .eq("id", roomId)
    .maybeSingle()

  if (roomErr) {
    console.error("[api/notifications/room-join] room lookup failed", roomErr)
    return Response.json({ error: roomErr.message }, { status: 500 })
  }

  if (!roomRow) {
    return Response.json({ error: "Room not found" }, { status: 404 })
  }

  if (!roomRow.owner_user_id || roomRow.owner_user_id === user.id) {
    return Response.json({ ok: true, skipped: true })
  }

  const { error: insertErr } = await supabaseServiceRole
    .from("notifications")
    .insert({
      user_id: roomRow.owner_user_id,
      sender_id: user.id,
      type: "room_join",
      room_id: roomId,
      content: JSON.stringify({
        room_slug: roomRow.slug ?? null,
        room_name: roomRow.name ?? null,
      }),
    })

  if (insertErr) {
    if (insertErr.code === "23505") {
      return Response.json({ ok: true, deduplicated: true })
    }
    console.error("[api/notifications/room-join] insert failed", insertErr)
    return Response.json({ error: insertErr.message }, { status: 500 })
  }

  const { scheduleIosPushDelivery } = await import(
    "@/lib/server/push/deliverPushNotification"
  )
  scheduleIosPushDelivery({
    recipientUserId: String(roomRow.owner_user_id),
    type: "room_join",
    sender_id: user.id,
    room_id: roomId,
    content: JSON.stringify({
      room_slug: roomRow.slug ?? null,
      room_name: roomRow.name ?? null,
    }),
    prefsAlreadyChecked: true,
  })

  return Response.json({ ok: true })
}
