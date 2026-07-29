import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { buildDirectMessagePushPreview } from "@/lib/server/push/dmPushPreview"
import { scheduleDmConversationPush } from "@/lib/server/push/dmConversationPush"
import { filterRecipientsByDmMessageTypePreference } from "@/lib/serverNotificationPreferences"
import type { MessagingPushPreferenceKey } from "@/lib/server/push/messagingPush"
import { jsonUserFacingError } from "@/lib/userFacingError"

/**
 * Drop recipients who have a block either direction with the sender.
 * Service-role query — recipients must not receive previews they cannot open.
 */
async function filterBlockedRecipients(
  senderId: string,
  recipientIds: string[]
): Promise<string[]> {
  if (recipientIds.length === 0) return []

  const recipientSet = new Set(recipientIds)

  const { data, error } = await supabaseServiceRole
    .from("user_blocks")
    .select("blocker_id, blocked_id")
    .or(`blocker_id.eq.${senderId},blocked_id.eq.${senderId}`)

  if (error) {
    console.error("[api/messaging/notify-dm] block lookup failed", error)
    // Fail closed: do not send previews when block status is unknown.
    return []
  }

  const blocked = new Set<string>()
  for (const row of data ?? []) {
    const blocker = String(row.blocker_id ?? "").trim()
    const blockedId = String(row.blocked_id ?? "").trim()
    if (blocker === senderId && recipientSet.has(blockedId)) {
      blocked.add(blockedId)
    }
    if (blockedId === senderId && recipientSet.has(blocker)) {
      blocked.add(blocker)
    }
  }

  return recipientIds.filter((id) => !blocked.has(id))
}

/**
 * Direct Message / conversation push — Messaging only (never Activity).
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
    .from("messages")
    .select(
      "id, conversation_id, sender_id, content, type, image_url, deleted_for_everyone, is_system"
    )
    .eq("id", messageId)
    .maybeSingle()

  if (messageErr) {
    return jsonUserFacingError(messageErr, 500, "[api/messaging/notify-dm] lookup")
  }

  if (!messageRow) {
    return Response.json({ error: "Message not found" }, { status: 404 })
  }

  if (messageRow.sender_id !== user.id) {
    return Response.json({ error: "Forbidden" }, { status: 403 })
  }

  // Never push previews for deleted or system messages.
  const preview = buildDirectMessagePushPreview(messageRow)
  if (!preview) {
    return Response.json({ ok: true, pushed: 0, skipped: "not_previewable" })
  }

  const conversationId = String(messageRow.conversation_id ?? "").trim()
  if (!conversationId) {
    return Response.json({ error: "Invalid conversation" }, { status: 400 })
  }

  const { data: conversationRow, error: conversationErr } =
    await supabaseServiceRole
      .from("conversations")
      .select("id, name, is_group")
      .eq("id", conversationId)
      .maybeSingle()

  if (conversationErr) {
    return jsonUserFacingError(
      conversationErr,
      500,
      "[api/messaging/notify-dm] conversation"
    )
  }

  const { data: participants, error: participantsErr } = await supabaseServiceRole
    .from("conversation_participants")
    .select("user_id")
    .eq("conversation_id", conversationId)
    .neq("user_id", user.id)

  if (participantsErr) {
    return jsonUserFacingError(
      participantsErr,
      500,
      "[api/messaging/notify-dm] participants"
    )
  }

  let recipientIds = (participants ?? [])
    .map((row) => String(row.user_id))
    .filter(Boolean)

  if (recipientIds.length === 0) {
    return Response.json({ ok: true, pushed: 0 })
  }

  const { data: mutedPrefs, error: mutedErr } = await supabaseServiceRole
    .from("conversation_member_preferences")
    .select("user_id")
    .eq("conversation_id", conversationId)
    .eq("notifications_enabled", false)
    .in("user_id", recipientIds)

  if (mutedErr) {
    console.error("[api/messaging/notify-dm] mute lookup failed", mutedErr)
    return Response.json({ error: mutedErr.message }, { status: 500 })
  }

  const muted = new Set((mutedPrefs ?? []).map((row) => String(row.user_id)))
  recipientIds = recipientIds.filter((id) => !muted.has(id))

  recipientIds = await filterBlockedRecipients(user.id, recipientIds)
  recipientIds = await filterRecipientsByDmMessageTypePreference(
    recipientIds,
    messageRow.type
  )

  if (recipientIds.length === 0) {
    return Response.json({
      ok: true,
      pushed: 0,
      skipped: "preferences_mute_or_block",
    })
  }

  const isGroup = conversationRow?.is_group === true
  const groupName =
    typeof conversationRow?.name === "string"
      ? conversationRow.name.trim()
      : ""

  const messageType = String(messageRow.type ?? "").trim()
  let preferenceKey: MessagingPushPreferenceKey = "direct_messages_enabled"
  if (messageType === "story_reply") {
    preferenceKey = "story_replies_enabled"
  } else if (
    messageType === "trade" ||
    messageType === "post" ||
    messageType === "profile_post" ||
    messageType === "achievement_post"
  ) {
    preferenceKey = "shares_enabled"
  }

  for (const recipientId of recipientIds) {
    void scheduleDmConversationPush({
      recipientUserId: recipientId,
      conversationId,
      messageId,
      senderId: user.id,
      preview,
      isGroup,
      groupName: isGroup ? groupName || "Group" : null,
      preferenceKey,
    })
  }

  return Response.json({ ok: true, pushed: recipientIds.length })
}
