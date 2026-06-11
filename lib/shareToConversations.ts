import type { SupabaseClient } from "@supabase/supabase-js"
import { compressImage } from "./compressImage"
import { logSupabaseError } from "./logSupabaseError"
import { assertSenderOwnsTrade } from "./tradeShareAccess"

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

function notifyConversationUpdated(
  conversationId: string,
  last_message: string,
  last_message_at: string
) {
  if (typeof window === "undefined") return
  window.dispatchEvent(
    new CustomEvent("tj-conversation-updated", {
      detail: { conversationId, last_message, last_message_at },
    })
  )
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
  const lastMessageAt = new Date().toISOString()

  for (const conversationId of opts.conversationIds) {
    const payload = {
      conversation_id: conversationId,
      sender_id: opts.senderId,
      type: "trade",
      trade_id: opts.tradeId,
      content,
      channel: null,
    }
    const { error } = await supabase.from("messages").insert(payload)
    if (error) {
      logSupabaseError("sendTradeToConversations insert", error, {
        table: "messages",
        query: "insert",
        payload,
        userId: opts.senderId,
        conversationId,
      })
      return { error: new Error(error.message) }
    }

    await supabase
      .from("conversations")
      .update({
        last_message: content,
        last_message_at: lastMessageAt,
      })
      .eq("id", conversationId)

    notifyConversationUpdated(conversationId, content, lastMessageAt)
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
  const lastMessageAt = new Date().toISOString()

  for (const conversationId of opts.conversationIds) {
    const payload = {
      conversation_id: conversationId,
      sender_id: opts.senderId,
      content: content || null,
      image_url: imageUrl,
      channel: null,
    }
    const { error } = await supabase.from("messages").insert(payload)
    if (error) {
      logSupabaseError("sendImageDataUrlToConversations insert", error, {
        table: "messages",
        query: "insert",
        payload,
        userId: opts.senderId,
        conversationId,
      })
      return { error: new Error(error.message) }
    }

    await supabase
      .from("conversations")
      .update({
        last_message: lastMsg,
        last_message_at: lastMessageAt,
      })
      .eq("id", conversationId)

    notifyConversationUpdated(conversationId, lastMsg, lastMessageAt)
  }

  return { error: null }
}
