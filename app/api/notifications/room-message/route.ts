import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { resolveMentionedUserIdsFromContent } from "@/lib/server/messaging/parseRoomMessageMentions"
import {
  filterRecipientsByRoomMentionPreference,
  filterRecipientsByRoomMessagePreference,
} from "@/lib/serverNotificationPreferences"
import { scheduleMessagingPush } from "@/lib/server/push/messagingPush"
import { jsonUserFacingError } from "@/lib/userFacingError"

type RoomMessageMeta = {
  message_id: string
  room_id: string
  room_slug?: string | null
  room_name?: string | null
  section_id?: string | null
  section_name?: string | null
  message_preview?: string | null
  sender_username?: string | null
  sender_name?: string | null
  is_reply?: boolean
}

function buildMessagePreview(
  content: string | null | undefined,
  type?: string | null
): string {
  if (type === "trade") return "Shared a trade"
  if (type === "image") return "Photo"
  const text = String(content ?? "").trim()
  if (!text) return "New message"
  if (text.length <= 100) return text
  const slice = text.slice(0, 100).trimEnd()
  const lastSpace = slice.lastIndexOf(" ")
  const base =
    lastSpace >= 60 ? slice.slice(0, lastSpace) : slice
  return `${base}…`
}

async function filterChannelMuted(
  roomId: string,
  sectionId: string,
  recipientIds: string[]
): Promise<string[]> {
  if (recipientIds.length === 0) return []

  const { data: mutedPrefs, error: prefsErr } = await supabaseServiceRole
    .from("room_member_channel_preferences")
    .select("user_id")
    .eq("room_id", roomId)
    .eq("section_id", sectionId)
    .eq("notifications_enabled", false)
    .in("user_id", recipientIds)

  if (prefsErr) {
    console.error(
      "[api/notifications/room-message] channel prefs lookup failed",
      prefsErr
    )
    throw prefsErr
  }

  const mutedUserIds = new Set(
    (mutedPrefs ?? []).map((row) => String(row.user_id))
  )
  return recipientIds.filter((id) => !mutedUserIds.has(id))
}

/**
 * Trade Room message fanout:
 * - Ordinary members → Messaging push only (no Activity row)
 * - @mentioned members → Activity `room_mention` + push (skip generic room push)
 */
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
    .select("id, room_id, user_id, content, type, section_id, parent_message_id")
    .eq("id", messageId)
    .maybeSingle()

  if (messageErr) {
    return jsonUserFacingError(messageErr, 500, "[api/notifications/room-message] lookup")
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
    return jsonUserFacingError(
      senderMemberErr,
      500,
      "[api/notifications/room-message] sender membership"
    )
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

  const { data: senderProfile } = await supabaseServiceRole
    .from("profiles")
    .select("username, name")
    .eq("id", user.id)
    .maybeSingle()

  const preview = buildMessagePreview(messageRow.content, messageRow.type)

  const payload: RoomMessageMeta = {
    message_id: messageId,
    room_id: messageRow.room_id,
    room_slug: roomRow?.slug ?? null,
    room_name: roomRow?.name ?? null,
    section_id: messageRow.section_id ?? null,
    section_name: sectionName,
    message_preview: preview,
    sender_username: senderProfile?.username
      ? String(senderProfile.username)
      : null,
    sender_name: senderProfile?.name ? String(senderProfile.name) : null,
    is_reply: Boolean(messageRow.parent_message_id),
  }
  const content = JSON.stringify(payload)

  // --- Mentions (Activity + push); may include muted-room members ---
  const mentionedIds = await resolveMentionedUserIdsFromContent(
    messageRow.content,
    { excludeUserId: user.id }
  )

  let mentionRecipients: string[] = []
  if (mentionedIds.length > 0) {
    const { data: mentionMembers, error: mentionMembersErr } =
      await supabaseServiceRole
        .from("room_members")
        .select("user_id")
        .eq("room_id", messageRow.room_id)
        .is("left_at", null)
        .in("user_id", mentionedIds)

    if (mentionMembersErr) {
      console.error(
        "[api/notifications/room-message] mention members lookup failed",
        mentionMembersErr
      )
      return Response.json({ error: mentionMembersErr.message }, { status: 500 })
    }

    mentionRecipients = (mentionMembers ?? [])
      .map((row) => String(row.user_id))
      .filter(Boolean)

    mentionRecipients = await filterRecipientsByRoomMentionPreference(
      mentionRecipients
    )

    if (messageRow.section_id && mentionRecipients.length > 0) {
      try {
        mentionRecipients = await filterChannelMuted(
          messageRow.room_id,
          messageRow.section_id,
          mentionRecipients
        )
      } catch (err) {
        const message = err instanceof Error ? err.message : "channel prefs failed"
        return Response.json({ error: message }, { status: 500 })
      }
    }
  }

  const mentionedSet = new Set(mentionRecipients)
  let mentionsInserted = 0

  if (mentionRecipients.length > 0) {
    const { data: existingMentions, error: existingMentionErr } =
      await supabaseServiceRole
        .from("notifications")
        .select("user_id")
        .eq("type", "room_mention")
        .eq("room_message_id", messageId)
        .in("user_id", mentionRecipients)

    if (existingMentionErr) {
      console.error(
        "[api/notifications/room-message] mention duplicate lookup failed",
        existingMentionErr
      )
      return Response.json({ error: existingMentionErr.message }, { status: 500 })
    }

    const alreadyMentioned = new Set(
      (existingMentions ?? []).map((row) => String(row.user_id))
    )

    const mentionRows = mentionRecipients
      .filter((id) => !alreadyMentioned.has(id))
      .map((recipientId) => ({
        user_id: recipientId,
        sender_id: user.id,
        type: "room_mention",
        room_message_id: messageId,
        content,
      }))

    if (mentionRows.length > 0) {
      const { error: insertErr } = await supabaseServiceRole
        .from("notifications")
        .insert(mentionRows)

      if (insertErr) {
        if (insertErr.code !== "23505") {
          console.error(
            "[api/notifications/room-message] mention insert failed",
            insertErr
          )
          return Response.json({ error: insertErr.message }, { status: 500 })
        }
      } else {
        mentionsInserted = mentionRows.length
      }

      const { scheduleIosPushDelivery } = await import(
        "@/lib/server/push/deliverPushNotification"
      )
      for (const row of mentionRows) {
        scheduleIosPushDelivery({
          recipientUserId: String(row.user_id),
          type: "room_mention",
          sender_id: user.id,
          content: row.content,
          prefsAlreadyChecked: true,
        })
      }
    }
  }

  // --- Ordinary room members → Messaging push only (no Activity) ---
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

  let messagingRecipients = (members ?? [])
    .map((row) => String(row.user_id))
    .filter((id) => id && !mentionedSet.has(id))

  messagingRecipients =
    await filterRecipientsByRoomMessagePreference(messagingRecipients)

  if (messageRow.section_id && messagingRecipients.length > 0) {
    try {
      messagingRecipients = await filterChannelMuted(
        messageRow.room_id,
        messageRow.section_id,
        messagingRecipients
      )
    } catch (err) {
      const message = err instanceof Error ? err.message : "channel prefs failed"
      return Response.json({ error: message }, { status: 500 })
    }
  }

  for (const recipientId of messagingRecipients) {
    if (messageRow.parent_message_id) {
      // Direct replies always bypass room digest batching.
      scheduleMessagingPush({
        recipientUserId: recipientId,
        kind: "room_message",
        sender_id: user.id,
        content,
        prefsAlreadyChecked: true,
      })
    } else {
      const { scheduleSmartRoomMessagePush } = await import(
        "@/lib/server/push/smartRoomPush"
      )
      void scheduleSmartRoomMessagePush({
        recipientUserId: recipientId,
        senderId: user.id,
        roomId: messageRow.room_id,
        content,
      })
    }
  }

  return Response.json({
    ok: true,
    mentionsInserted,
    messagingPushed: messagingRecipients.length,
  })
}
