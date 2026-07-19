import type { SupabaseClient } from "@supabase/supabase-js"
import { compressScreenshot } from "./compressImage"
import { ensureDmConversation } from "./dmConversation"
import { logSupabaseError } from "./logSupabaseError"
import { assertSenderOwnsTrade } from "./tradeShareAccess"
import {
  dispatchConversationInboxPatch,
  previewFromMessage,
  updateConversationPreview,
} from "./conversationInboxSync"
import { fetchHiddenBlockedDmConversationIds } from "./conversationBlocks"

export type ShareConversationRow = {
  id: string
  name: string
  avatar_url: string
  is_group: boolean
  last_message_at?: string | null
  /** DM counterpart — used to exclude from user search. */
  other_user_id?: string | null
}

export type DmConversationParticipantProfile = {
  id: string
  username: string | null
  avatar_url: string | null
  name?: string | null
}

export type DmConversationParticipant = {
  user_id: string
  profiles: DmConversationParticipantProfile | null
}

/** Row shape from the shared two-step DM conversation loader. */
export type DmConversationRow = {
  id: string
  is_group: boolean
  is_pinned: boolean
  name: string | null
  avatar_url: string | null
  last_message: string | null
  last_message_at: string | null
  participants: DmConversationParticipant[]
}

function normalizeEmbeddedProfile(
  raw: unknown
): DmConversationParticipantProfile | null {
  if (!raw) return null
  const row = Array.isArray(raw) ? raw[0] : raw
  if (!row || typeof row !== "object") return null
  const p = row as Record<string, unknown>
  return {
    id: String(p.id ?? ""),
    username: (p.username as string | null) ?? null,
    avatar_url: (p.avatar_url as string | null) ?? null,
    name: (p.name as string | null) ?? null,
  }
}

function normalizeDmConversationRow(conv: Record<string, unknown>): DmConversationRow {
  const participantsRaw = Array.isArray(conv.participants) ? conv.participants : []
  const participants: DmConversationParticipant[] = participantsRaw.map((p) => {
    const row = p as Record<string, unknown>
    return {
      user_id: String(row.user_id ?? ""),
      profiles: normalizeEmbeddedProfile(row.profiles),
    }
  })

  return {
    id: String(conv.id ?? ""),
    is_group: conv.is_group === true,
    is_pinned: conv.is_pinned === true,
    name: (conv.name as string | null) ?? null,
    avatar_url: (conv.avatar_url as string | null) ?? null,
    last_message: (conv.last_message as string | null) ?? null,
    last_message_at: (conv.last_message_at as string | null) ?? null,
    participants,
  }
}

/**
 * Shared DM conversation loader (messages inbox + share-to-DM):
 * 1) conversation_participants → conversation_id
 * 2) conversations + participants embed
 */
export async function fetchUserDmConversations(
  supabase: SupabaseClient,
  userId: string
): Promise<{ rows: DmConversationRow[]; error: Error | null }> {
  console.log("SHARED_LOADER_CALLED", { userId })

  const [
    { data: membershipRows, error: membershipError },
    hiddenBlockedConversationIds,
  ] = await Promise.all([
    supabase
      .from("conversation_participants")
      .select("conversation_id")
      .eq("user_id", userId),
    fetchHiddenBlockedDmConversationIds(supabase),
  ])

  if (membershipError) {
    console.error("fetchUserDmConversations participants:", membershipError)
    return { rows: [], error: new Error(membershipError.message) }
  }

  const conversationIds = [
    ...new Set(
      (membershipRows || [])
        .map((row: { conversation_id: string }) => row.conversation_id)
        .filter((id) => !hiddenBlockedConversationIds.has(id))
    ),
  ]

  if (conversationIds.length === 0) {
    return { rows: [], error: null }
  }

  const { data, error } = await supabase
    .from("conversations")
    .select(
      `
      id,
      is_group,
      is_pinned,
      name,
      avatar_url,
      last_message,
      last_message_at,
      participants:conversation_participants(
        user_id,
        profiles (
          id,
          username,
          avatar_url,
          name
        )
      )
    `
    )
    .in("id", conversationIds)

  if (error) {
    console.error("fetchUserDmConversations conversations:", error)
    return { rows: [], error: new Error(error.message) }
  }

  return {
    rows: (data || []).map((row) =>
      normalizeDmConversationRow(row as Record<string, unknown>)
    ),
    error: null,
  }
}

/** Same query flow as the messages inbox — share modal display mapping only. */
export async function fetchShareConversations(
  supabase: SupabaseClient,
  userId: string
): Promise<ShareConversationRow[]> {
  const { rows, error } = await fetchUserDmConversations(supabase, userId)

  if (error) {
    return []
  }

  const mapped = rows.map((conv) => {
    const otherUser = conv.participants.find((p) => p.user_id !== userId)
    const otherProfile = otherUser?.profiles

    const displayName = conv.is_group
      ? conv.name || "Group Chat"
      : otherProfile?.username || "User"
    const displayAvatar = conv.is_group
      ? conv.avatar_url || null
      : otherProfile?.avatar_url || null

    return {
      id: conv.id,
      name: displayName,
      is_group: conv.is_group,
      avatar_url: displayAvatar ?? "",
      last_message_at: conv.last_message_at ?? null,
      other_user_id: conv.is_group ? null : otherUser?.user_id ?? null,
    }
  })

  return mapped.sort(
    (a, b) =>
      new Date(b.last_message_at || 0).getTime() -
      new Date(a.last_message_at || 0).getTime()
  )
}

/** Resolve conversation ids from existing chats and/or new DM targets. */
export async function resolveShareRecipientConversationIds(
  supabase: SupabaseClient,
  senderId: string,
  conversationIds: string[],
  userIds: string[]
): Promise<{ conversationIds: string[]; error: Error | null }> {
  const resolved = new Set(conversationIds)

  for (const otherUserId of userIds) {
    const result = await ensureDmConversation(supabase, senderId, otherUserId)
    if (!result.ok) {
      return {
        conversationIds: [],
        error: new Error(result.error.message),
      }
    }
    resolved.add(result.conversationId)
  }

  return { conversationIds: [...resolved], error: null }
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

/** Card first, optional caption as a follow-up text message (same sender, sequential). */
async function sendShareCardSequence(
  supabase: SupabaseClient,
  opts: {
    senderId: string
    conversationId: string
    cardPayload: Record<string, unknown>
    caption?: string | null
    logLabel: string
    cardPreview: { type?: string | null; image_url?: string | null }
  }
): Promise<{ error: Error | null }> {
  const caption = opts.caption?.trim() ?? ""

  const { createdAt: cardAt, error: cardErr } = await insertShareMessage(
    supabase,
    { ...opts.cardPayload, content: null },
    {
      label: opts.logLabel,
      userId: opts.senderId,
      conversationId: opts.conversationId,
    }
  )
  if (cardErr || !cardAt) {
    return { error: cardErr ?? new Error("Message insert failed") }
  }

  let lastAt = cardAt
  let lastPreview = previewFromMessage(opts.cardPreview)

  if (caption) {
    const { createdAt: textAt, error: textErr } = await insertShareMessage(
      supabase,
      {
        conversation_id: opts.conversationId,
        sender_id: opts.senderId,
        content: caption,
        channel: null,
      },
      {
        label: `${opts.logLabel}:caption`,
        userId: opts.senderId,
        conversationId: opts.conversationId,
      }
    )
    if (textErr || !textAt) {
      return { error: textErr ?? new Error("Caption insert failed") }
    }
    lastAt = textAt
    lastPreview = previewFromMessage({ content: caption })
  }

  await syncConversationAfterSend(
    supabase,
    opts.conversationId,
    lastPreview,
    lastAt
  )

  return { error: null }
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

  const caption = opts.content?.trim() ?? ""

  for (const conversationId of opts.conversationIds) {
    const { error } = await sendShareCardSequence(supabase, {
      senderId: opts.senderId,
      conversationId,
      caption,
      logLabel: "sendTradeToConversations",
      cardPayload: {
        conversation_id: conversationId,
        sender_id: opts.senderId,
        type: "trade",
        trade_id: opts.tradeId,
        channel: null,
      },
      cardPreview: { type: "trade" },
    })
    if (error) {
      return { error }
    }
  }

  return { error: null }
}

export async function sendPostToConversations(
  supabase: SupabaseClient,
  opts: {
    senderId: string
    conversationIds: string[]
    postId: string
    feedKind?: "trade" | "profile" | "achievement" | "reel"
    content?: string
  }
): Promise<{ error: Error | null }> {
  const caption = opts.content?.trim() ?? ""
  const feedKind = opts.feedKind ?? "trade"

  for (const conversationId of opts.conversationIds) {
    const cardPayload =
      feedKind === "profile"
        ? {
            conversation_id: conversationId,
            sender_id: opts.senderId,
            type: "profile_post",
            profile_post_id: opts.postId,
            channel: null,
          }
        : feedKind === "achievement"
          ? {
              conversation_id: conversationId,
              sender_id: opts.senderId,
              type: "achievement_post",
              achievement_post_id: opts.postId,
              channel: null,
            }
          : feedKind === "reel"
            ? {
                conversation_id: conversationId,
                sender_id: opts.senderId,
                type: "reel",
                reel_id: opts.postId,
                channel: null,
              }
            : {
                conversation_id: conversationId,
                sender_id: opts.senderId,
                type: "post",
                post_id: opts.postId,
                channel: null,
              }

    const cardPreviewType =
      feedKind === "profile"
        ? "profile_post"
        : feedKind === "achievement"
          ? "achievement_post"
          : feedKind === "reel"
            ? "reel"
            : "post"

    const { error } = await sendShareCardSequence(supabase, {
      senderId: opts.senderId,
      conversationId,
      caption,
      logLabel: "sendPostToConversations",
      cardPayload,
      cardPreview: { type: cardPreviewType },
    })
    if (error) {
      return { error }
    }
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
    uploadFile = await compressScreenshot(uploadFile)
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
