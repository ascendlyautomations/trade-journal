import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

type RoomMessageMeta = {
  message_id: string
  room_id: string
  room_slug?: string | null
  room_name?: string | null
  section_id?: string | null
  section_name?: string | null
  message_preview?: string | null
}

function buildMessagePreview(content: string | null | undefined): string {
  const text = String(content ?? "").trim()
  if (!text) return "New message"
  if (text.length <= 120) return text
  return `${text.slice(0, 120).trim()}…`
}

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let messageId: string | undefined
  try {
    const body = (await req.json()) as { messageId?: string }
    messageId = body.messageId?.trim()
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  if (!messageId) {
    return Response.json({ error: "Invalid messageId" }, { status: 400 })
  }

  const { data: messageRow, error: messageErr } = await supabaseServiceRole
    .from("room_messages")
    .select("id, room_id, user_id, content, type, section_id")
    .eq("id", messageId)
    .maybeSingle()

  if (messageErr) {
    console.error("[api/notifications/room-message] message lookup failed", messageErr)
    return Response.json({ error: messageErr.message }, { status: 500 })
  }

  if (!messageRow) {
    return Response.json({ error: "Message not found" }, { status: 404 })
  }

  if (messageRow.user_id !== user.id) {
    return Response.json({ error: "Forbidden" }, { status: 403 })
  }

  const { data: senderMember, error: senderMemberErr } = await supabaseServiceRole
    .from("room_members")
    .select("id")
    .eq("room_id", messageRow.room_id)
    .eq("user_id", user.id)
    .is("left_at", null)
    .maybeSingle()

  if (senderMemberErr) {
    console.error(
      "[api/notifications/room-message] sender membership lookup failed",
      senderMemberErr
    )
    return Response.json({ error: senderMemberErr.message }, { status: 500 })
  }

  if (!senderMember) {
    return Response.json(
      { error: "Active room membership not found" },
      { status: 404 }
    )
  }

  const { data: roomRow, error: roomErr } = await supabaseServiceRole
    .from("rooms")
    .select("name, slug")
    .eq("id", messageRow.room_id)
    .maybeSingle()

  if (roomErr) {
    console.error("[api/notifications/room-message] room lookup failed", roomErr)
    return Response.json({ error: roomErr.message }, { status: 500 })
  }

  let sectionName: string | null = null
  if (messageRow.section_id) {
    const { data: sectionRow } = await supabaseServiceRole
      .from("room_sections")
      .select("name")
      .eq("id", messageRow.section_id)
      .maybeSingle()
    sectionName = sectionRow?.name ?? null
  }

  const { data: members, error: membersErr } = await supabaseServiceRole
    .from("room_members")
    .select("user_id")
    .eq("room_id", messageRow.room_id)
    .eq("notification_enabled", true)
    .is("left_at", null)
    .neq("user_id", user.id)

  if (membersErr) {
    console.error("[api/notifications/room-message] members lookup failed", membersErr)
    return Response.json({ error: membersErr.message }, { status: 500 })
  }

  let recipientIds = (members ?? [])
    .map((row) => String(row.user_id))
    .filter(Boolean)

  if (recipientIds.length === 0) {
    return Response.json({ ok: true, inserted: 0 })
  }

  if (messageRow.section_id) {
    const { data: mutedPrefs, error: prefsErr } = await supabaseServiceRole
      .from("room_member_channel_preferences")
      .select("user_id")
      .eq("room_id", messageRow.room_id)
      .eq("section_id", messageRow.section_id)
      .eq("notifications_enabled", false)
      .in("user_id", recipientIds)

    if (prefsErr) {
      console.error(
        "[api/notifications/room-message] channel prefs lookup failed",
        prefsErr
      )
      return Response.json({ error: prefsErr.message }, { status: 500 })
    }

    const mutedUserIds = new Set(
      (mutedPrefs ?? []).map((row) => String(row.user_id))
    )
    recipientIds = recipientIds.filter((id) => !mutedUserIds.has(id))
  }

  if (recipientIds.length === 0) {
    return Response.json({ ok: true, inserted: 0, skipped: "channel_muted" })
  }

  const { data: existingRows, error: existingErr } = await supabaseServiceRole
    .from("notifications")
    .select("user_id")
    .eq("type", "room_message")
    .in("user_id", recipientIds)
    .like("content", `%\"message_id\":\"${messageId}\"%`)

  if (existingErr) {
    console.error(
      "[api/notifications/room-message] duplicate lookup failed",
      existingErr
    )
    return Response.json({ error: existingErr.message }, { status: 500 })
  }

  const alreadyNotified = new Set(
    (existingRows ?? []).map((row) => String(row.user_id))
  )

  const preview =
    messageRow.type === "trade"
      ? "Shared a trade"
      : messageRow.type === "image"
        ? "Sent an image"
        : buildMessagePreview(messageRow.content)

  const payload: RoomMessageMeta = {
    message_id: messageId,
    room_id: messageRow.room_id,
    room_slug: roomRow?.slug ?? null,
    room_name: roomRow?.name ?? null,
    section_id: messageRow.section_id ?? null,
    section_name: sectionName,
    message_preview: preview,
  }

  const content = JSON.stringify(payload)
  const rows = recipientIds
    .filter((recipientId) => !alreadyNotified.has(recipientId))
    .map((recipientId) => ({
      user_id: recipientId,
      sender_id: user.id,
      type: "room_message",
      content,
    }))

  if (rows.length === 0) {
    return Response.json({ ok: true, inserted: 0, skipped: recipientIds.length })
  }

  const { error: insertErr } = await supabaseServiceRole
    .from("notifications")
    .insert(rows)

  if (insertErr) {
    console.error("[api/notifications/room-message] insert failed", insertErr)
    return Response.json({ error: insertErr.message }, { status: 500 })
  }

  return Response.json({ ok: true, inserted: rows.length })
}
