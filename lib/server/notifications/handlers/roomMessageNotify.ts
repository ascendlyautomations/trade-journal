import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { resolveMentionedUserIdsFromContent } from "@/lib/server/messaging/parseRoomMessageMentions"
import {
  emitActivityNotification,
  emitMessagingPush,
} from "@/lib/server/notifications/emit"
import {
  filterRecipientsByRoomMentionPreference,
  filterRecipientsByRoomMessagePreference,
} from "@/lib/serverNotificationPreferences"

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
  const base = lastSpace >= 60 ? slice.slice(0, lastSpace) : slice
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
export async function notifyRoomMessage(
  actorUserId: string,
  messageId: string
): Promise<
  | { ok: true; mentionsInserted?: number; messagingPushed?: number }
  | { ok: false; error: string; status: number }
> {
  const { data: messageRow, error: messageErr } = await supabaseServiceRole
    .from("room_messages")
    .select("id, room_id, user_id, content, type, section_id, parent_message_id")
    .eq("id", messageId)
    .maybeSingle()

  if (messageErr) {
    console.error("[api/notifications/room-message] lookup", messageErr)
    return { ok: false, error: messageErr.message, status: 500 }
  }

  if (!messageRow) {
    return { ok: false, error: "Message not found", status: 404 }
  }

  const roomId = messageRow.room_id
  if (!roomId) {
    return { ok: false, error: "Message room not found", status: 404 }
  }

  if (messageRow.user_id !== actorUserId) {
    return { ok: false, error: "Forbidden", status: 403 }
  }

  const { data: senderMember, error: senderMemberErr } = await supabaseServiceRole
    .from("room_members")
    .select("id")
    .eq("room_id", roomId)
    .eq("user_id", actorUserId)
    .is("left_at", null)
    .maybeSingle()

  if (senderMemberErr) {
    console.error(
      "[api/notifications/room-message] sender membership",
      senderMemberErr
    )
    return { ok: false, error: senderMemberErr.message, status: 500 }
  }

  if (!senderMember) {
    return {
      ok: false,
      error: "Active room membership not found",
      status: 404,
    }
  }

  const { data: roomRow, error: roomErr } = await supabaseServiceRole
    .from("rooms")
    .select("name, slug")
    .eq("id", roomId)
    .maybeSingle()

  if (roomErr) {
    console.error("[api/notifications/room-message] room lookup failed", roomErr)
    return { ok: false, error: roomErr.message, status: 500 }
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
    .eq("id", actorUserId)
    .maybeSingle()

  const preview = buildMessagePreview(messageRow.content, messageRow.type)

  const payload: RoomMessageMeta = {
    message_id: messageId,
    room_id: roomId,
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
    { excludeUserId: actorUserId }
  )

  let mentionRecipients: string[] = []
  if (mentionedIds.length > 0) {
    const { data: mentionMembers, error: mentionMembersErr } =
      await supabaseServiceRole
        .from("room_members")
        .select("user_id")
        .eq("room_id", roomId)
        .is("left_at", null)
        .in("user_id", mentionedIds)

    if (mentionMembersErr) {
      console.error(
        "[api/notifications/room-message] mention members lookup failed",
        mentionMembersErr
      )
      return { ok: false, error: mentionMembersErr.message, status: 500 }
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
          roomId,
          messageRow.section_id,
          mentionRecipients
        )
      } catch (err) {
        const message =
          err instanceof Error ? err.message : "channel prefs failed"
        return { ok: false, error: message, status: 500 }
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
      return { ok: false, error: existingMentionErr.message, status: 500 }
    }

    const alreadyMentioned = new Set(
      (existingMentions ?? []).map((row) => String(row.user_id))
    )

    const mentionRows = mentionRecipients
      .filter((id) => !alreadyMentioned.has(id))
      .map((recipientId) => ({
        user_id: recipientId,
        sender_id: actorUserId,
        type: "room_mention",
        room_message_id: messageId,
        content,
      }))

    for (const row of mentionRows) {
      const result = await emitActivityNotification({
        row: {
          user_id: row.user_id,
          sender_id: row.sender_id,
          type: "room_mention",
          room_message_id: row.room_message_id,
          content: row.content,
        },
        push: {
          type: "room_mention",
          sender_id: actorUserId,
          content: row.content,
          prefsAlreadyChecked: true,
        },
        logLabel: "api/notifications/room-message",
      })

      if (!result.ok) {
        return { ok: false, error: result.error, status: 500 }
      }
      if (result.inserted) mentionsInserted += 1
    }
  }

  // --- Ordinary room members → Messaging push only (no Activity) ---
  const { data: members, error: membersErr } = await supabaseServiceRole
    .from("room_members")
    .select("user_id")
    .eq("room_id", roomId)
    .eq("notification_enabled", true)
    .is("left_at", null)
    .neq("user_id", actorUserId)

  if (membersErr) {
    console.error(
      "[api/notifications/room-message] members lookup failed",
      membersErr
    )
    return { ok: false, error: membersErr.message, status: 500 }
  }

  let messagingRecipients = (members ?? [])
    .map((row) => String(row.user_id))
    .filter((id) => id && !mentionedSet.has(id))

  messagingRecipients =
    await filterRecipientsByRoomMessagePreference(messagingRecipients)

  if (messageRow.section_id && messagingRecipients.length > 0) {
    try {
      messagingRecipients = await filterChannelMuted(
        roomId,
        messageRow.section_id,
        messagingRecipients
      )
    } catch (err) {
      const message =
        err instanceof Error ? err.message : "channel prefs failed"
      return { ok: false, error: message, status: 500 }
    }
  }

  for (const recipientId of messagingRecipients) {
    emitMessagingPush({
      recipientUserId: recipientId,
      kind: "room_message",
      sender_id: actorUserId,
      content,
      preferenceKey: "room_messages_enabled",
      prefsAlreadyChecked: true,
    })
  }

  return {
    ok: true,
    mentionsInserted,
    messagingPushed: messagingRecipients.length,
  }
}
