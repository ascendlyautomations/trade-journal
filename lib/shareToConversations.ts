import type { SupabaseClient } from "@supabase/supabase-js"
import { compressImage } from "./compressImage"
import { logSupabaseError } from "./logSupabaseError"
import { assertSenderOwnsTrade } from "./tradeShareAccess"
import {
  dispatchConversationInboxPatch,
  previewFromMessage,
  updateConversationPreview,
} from "./conversationInboxSync"

export type ShareConversationRow = {
  id: string
  name: string
  avatar_url: string
  is_group: boolean
}

/** Same query shape as `app/feed/page.tsx` share-to-DM loader. */
export async function fetchShareConversations(
  supabase: SupabaseClient,
  userId: string
): Promise<ShareConversationRow[]> {
  const { data: membershipRows, error: membershipError } = await supabase
    .from("conversation_participants")
    .select("conversation_id")
    .eq("user_id", userId)

  if (membershipError) {
    console.error("fetchShareConversations:", membershipError)
    return []
  }

  const conversationIds = [
    ...new Set((membershipRows || []).map((row: { conversation_id: string }) => row.conversation_id)),
  ]

  if (conversationIds.length === 0) return []

  const { data: rows, error } = await supabase
    .from("conversations")
    .select(
      `
      id,
      is_group,
      name,
      avatar_url,
      participants:conversation_participants(
        user_id,
        profiles (
          id,
          username,
          avatar_url
        )
      )
    `
    )
    .in("id", conversationIds)

  if (error) {
    console.error("fetchShareConversations conversations:", error)
    return []
  }

  return (rows || []).map((conv: any) => {
    const participants = Array.isArray(conv.participants) ? conv.participants : []
    const otherUser = participants.find((p: any) => p.user_id !== userId)
    const otherProfileRaw = otherUser?.profiles
    const otherProfile = Array.isArray(otherProfileRaw)
      ? otherProfileRaw[0]
      : otherProfileRaw

    const displayName = conv.is_group
      ? conv.name || "Group Chat"
      : otherProfile?.username || "User"
    const displayAvatar = conv.is_group
      ? conv.avatar_url || "/default-avatar.png"
      : otherProfile?.avatar_url || "/default-avatar.png"

    return {
      id: conv.id,
      name: displayName,
      is_group: conv.is_group === true,
      avatar_url: displayAvatar,
    }
  })
}

async function syncConversationAfterSend(
  supabase: SupabaseClient,
  conversationId: string,
  preview: string,
  lastMessageAt: string
) {
  await updateConversationPreview(supabase, conversationId, preview, lastMessageAt)
  dispatchConversationInboxPatch({
    conversationId,
    last_message: preview,
    last_message_at: lastMessageAt,
  })
}

async function insertShareMessage(
  supabase: SupabaseClient,
  payload: Record<string, unknown>,
  logContext: { label: string; userId: string; conversationId: string }
): Promise<{ createdAt: string | null; error: Error | null }> {
  const { data, error } = await supabase
    .from("messages")
    .insert(payload)
    .select("created_at")
    .single()

  if (error) {
    logSupabaseError(`${logContext.label} insert`, error, {
      table: "messages",
      query: "insert",
      payload,
      userId: logContext.userId,
      conversationId: logContext.conversationId,
    })
    return { createdAt: null, error: new Error(error.message) }
  }

  return {
    createdAt:
      data?.created_at != null ? String(data.created_at) : new Date().toISOString(),
    error: null,
  }
}

/** Same insert shape as `handleSendTrade` in `app/messages/[id]/page.tsx`. */
export async function sendTradeToConversations(
  supabase: SupabaseClient,
  opts: {
    senderId: string
    conversationIds: string[]
    tradeId: string
    content?: string
  }
): Promise<{ error: Error | null }> {
  const ownership = await assertSenderOwnsTrade(
    supabase,
    opts.tradeId,
    opts.senderId
  )
  if (!ownership.ok) {
    return { error: ownership.error }
  }

  const content = opts.content?.trim() || "Shared a trade"

  for (const conversationId of opts.conversationIds) {
    const payload = {
      conversation_id: conversationId,
      sender_id: opts.senderId,
      type: "trade",
      trade_id: opts.tradeId,
      content,
      channel: null,
    }
    const { createdAt, error } = await insertShareMessage(supabase, payload, {
      label: "sendTradeToConversations",
      userId: opts.senderId,
      conversationId,
    })
    if (error || !createdAt) {
      return { error: error ?? new Error("Message insert failed") }
    }

    await syncConversationAfterSend(
      supabase,
      conversationId,
      previewFromMessage({ content, type: "trade" }),
      createdAt
    )
  }

  return { error: null }
}

export async function sendPostToConversations(
  supabase: SupabaseClient,
  opts: {
    senderId: string
    conversationIds: string[]
    postId: string
    content?: string
  }
): Promise<{ error: Error | null }> {
  const content = opts.content?.trim() || "Shared a post"

  for (const conversationId of opts.conversationIds) {
    const payload = {
      conversation_id: conversationId,
      sender_id: opts.senderId,
      type: "post",
      post_id: opts.postId,
      content,
      channel: null,
    }
    const { createdAt, error } = await insertShareMessage(supabase, payload, {
      label: "sendPostToConversations",
      userId: opts.senderId,
      conversationId,
    })
    if (error || !createdAt) {
      return { error: error ?? new Error("Message insert failed") }
    }

    await syncConversationAfterSend(
      supabase,
      conversationId,
      previewFromMessage({ content, type: "post" }),
      createdAt
    )
  }

  return { error: null }
}

/**
 * Upload a PNG data URL to public screenshots bucket and send as a normal image message
 * (same pattern as `sendMessage` image path in `app/messages/[id]/page.tsx`).
 */
export async function sendImageDataUrlToConversations(
  supabase: SupabaseClient,
  opts: {
    senderId: string
    conversationIds: string[]
    dataUrl: string
    content?: string
  }
): Promise<{ error: Error | null }> {
  const res = await fetch(opts.dataUrl)
  const blob = await res.blob()
  let uploadFile = new File([blob], "share.png", {
    type: blob.type || "image/png",
  })
  if (uploadFile.type?.startsWith("image/")) {
    uploadFile = await compressImage(uploadFile)
  }
  const path = `${opts.senderId}/share-${Date.now()}-${uploadFile.name}`

  const { error: upErr } = await supabase.storage
    .from("screenshots")
    .upload(path, uploadFile, {
      contentType: uploadFile.type || "application/octet-stream",
      upsert: false,
    })

  if (upErr) {
    console.error("sendImageDataUrlToConversations upload:", upErr)
    return { error: new Error(upErr.message) }
  }

  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  const imageUrl = base
    ? `${base}/storage/v1/object/public/screenshots/${path}`
    : path

  const content = opts.content?.trim() || ""
  const lastMsg = content || "Image"

  for (const conversationId of opts.conversationIds) {
    const payload = {
      conversation_id: conversationId,
      sender_id: opts.senderId,
      content: content || null,
      image_url: imageUrl,
      channel: null,
    }
    const { createdAt, error } = await insertShareMessage(supabase, payload, {
      label: "sendImageDataUrlToConversations",
      userId: opts.senderId,
      conversationId,
    })
    if (error || !createdAt) {
      return { error: error ?? new Error("Message insert failed") }
    }

    await syncConversationAfterSend(
      supabase,
      conversationId,
      previewFromMessage({ content, image_url: imageUrl }),
      createdAt
    )
  }

  return { error: null }
}
