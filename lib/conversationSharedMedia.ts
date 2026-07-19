import type { SupabaseClient } from "@supabase/supabase-js"
import { supabase } from "@/lib/supabaseClient"

export const SHARED_MEDIA_PAGE_SIZE = 12

export type ConversationSharedMediaItem = {
  id: string
  senderId: string | null
  imageUrl: string
  createdAt: string
}

export type ConversationSharedMediaCursor = {
  createdAt: string
  id: string
}

export async function fetchConversationSharedMedia(
  conversationId: string,
  cursor: ConversationSharedMediaCursor | null = null,
  client: SupabaseClient = supabase
): Promise<
  | { ok: true; items: ConversationSharedMediaItem[] }
  | { ok: false; message: string }
> {
  const { data, error } = await client.rpc("get_conversation_shared_media", {
    p_conversation_id: conversationId,
    p_before_created_at: cursor?.createdAt ?? null,
    p_before_id: cursor?.id ?? null,
    p_limit: SHARED_MEDIA_PAGE_SIZE,
  })

  if (error) {
    return { ok: false, message: error.message }
  }

  const items: ConversationSharedMediaItem[] = (data ?? [])
    .map((raw: Record<string, unknown>): ConversationSharedMediaItem => ({
      id: String(raw.message_id ?? "").trim(),
      senderId:
        raw.sender_id == null ? null : String(raw.sender_id).trim() || null,
      imageUrl: String(raw.image_url ?? "").trim(),
      createdAt: String(raw.created_at ?? "").trim(),
    }))
    .filter(
      (item: ConversationSharedMediaItem) =>
        Boolean(item.id && item.imageUrl && item.createdAt)
    )

  return { ok: true, items }
}
