import type { SupabaseClient } from "@supabase/supabase-js"
import {
  dispatchConversationInboxPatch,
  previewFromMessage,
  updateConversationPreview,
} from "@/lib/conversationInboxSync"
import { ensureDmConversation } from "@/lib/dmConversation"
import { feedbackPresets } from "@/lib/feedbackPresets"
import { isFreePlanDailyDmLimitError } from "@/lib/freePlanMessagingLimits"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import {
  encodeStoryReplyContent,
  STORY_REPLY_MESSAGE_TYPE,
  type StoryReplyPayload,
} from "@/lib/storyReplyMessage"

export type SendStoryReplyParams = {
  senderId: string
  storyOwnerId: string
  story: { id: string; image_url: string }
  storyOwnerUsername?: string | null
  text: string
}

export type SendStoryReplyResult =
  | { ok: true; conversationId: string }
  | { ok: false; error: string }

export async function sendStoryReply(
  client: SupabaseClient,
  params: SendStoryReplyParams
): Promise<SendStoryReplyResult> {
  const trimmed = params.text.trim()
  if (!trimmed) {
    return { ok: false, error: "Reply cannot be empty" }
  }

  if (!params.senderId || !params.storyOwnerId) {
    return { ok: false, error: "Invalid participants" }
  }

  if (params.senderId === params.storyOwnerId) {
    return { ok: false, error: "You cannot reply to your own story" }
  }

  const ensured = await ensureDmConversation(
    client,
    params.senderId,
    params.storyOwnerId
  )

  if (!ensured.ok) {
    return {
      ok: false,
      error: handleSupabaseError(
        ensured.error,
        "Could not open conversation. Please try again."
      ),
    }
  }

  const payload: StoryReplyPayload = {
    text: trimmed,
    story_id: params.story.id,
    story_image_url: params.story.image_url,
    story_owner_id: params.storyOwnerId,
    story_owner_username: params.storyOwnerUsername ?? null,
  }

  const content = encodeStoryReplyContent(payload)
  const insertPayload = {
    conversation_id: ensured.conversationId,
    sender_id: params.senderId,
    type: STORY_REPLY_MESSAGE_TYPE,
    content,
    channel: null,
  }

  const { error: insertErr } = await client.from("messages").insert(insertPayload)
  if (insertErr) {
    if (isFreePlanDailyDmLimitError(insertErr)) {
      return { ok: false, error: feedbackPresets.directMessageLimitReached().message }
    }
    return { ok: false, error: handleSupabaseError(insertErr) }
  }

  const preview = previewFromMessage({
    content,
    type: STORY_REPLY_MESSAGE_TYPE,
  })
  const lastMessageAt = await updateConversationPreview(
    client,
    ensured.conversationId,
    preview
  )

  dispatchConversationInboxPatch({
    conversationId: ensured.conversationId,
    last_message: preview,
    last_message_at: lastMessageAt,
  })

  return { ok: true, conversationId: ensured.conversationId }
}
