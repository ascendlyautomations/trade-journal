import type { SupabaseClient } from "@supabase/supabase-js"
import { storyReplyPreviewText } from "@/lib/storyReplyMessage"
import {
  decodeStoryShareContent,
  storySharePreviewText,
} from "@/lib/storyShareMessage"

export const CONVERSATION_UPDATED_EVENT = "tj-conversation-updated"
export const INBOX_PATCHES_STORAGE_KEY = "tj-conversation-inbox-patches"

export type ConversationInboxPatch = {
  conversationId: string
  last_message: string
  last_message_at: string
}

export function conversationTimestampMs(value: string | null | undefined): number {
  if (!value) return 0
  const ms = new Date(value).getTime()
  return Number.isFinite(ms) ? ms : 0
}

/** True when incoming is newer than or equal to current (never downgrade sort order). */
export function isIncomingInboxTimestampNewerOrEqual(
  incoming: string | null | undefined,
  current: string | null | undefined
): boolean {
  return conversationTimestampMs(incoming) >= conversationTimestampMs(current)
}

export function mergeConversationInboxFields<
  T extends { lastMessage?: string; last_message_at?: string | null },
>(
  current: T,
  incoming: { last_message?: string; last_message_at?: string | null }
): T {
  const incomingAt = incoming.last_message_at
  if (
    incomingAt &&
    !isIncomingInboxTimestampNewerOrEqual(incomingAt, current.last_message_at)
  ) {
    return current
  }

  return {
    ...current,
    ...(incoming.last_message != null
      ? { lastMessage: incoming.last_message }
      : {}),
    ...(incomingAt ? { last_message_at: incomingAt } : {}),
  }
}

/** Same preview rules as `app/(app)/messages/page.tsx` realtime handler. */
export function previewFromMessage(row: {
  content?: string | null
  image_url?: string | null
  audio_url?: string | null
  type?: string | null
  deleted_for_everyone?: boolean | null
  is_system?: boolean | null
}): string {
  if (row.deleted_for_everyone) return "Message deleted"
  if (row.type === "story_reply") {
    return storyReplyPreviewText(row.content)
  }
  if (row.type === "story_share" || decodeStoryShareContent(row.content)) {
    return storySharePreviewText(row.content)
  }
  if (row.type?.toLowerCase() === "voice") return "Voice message"
  if (row.audio_url?.trim()) return "Voice message"
  if (row.content?.trim()) return row.content.trim()
  if (row.image_url) return "Image"
  if (row.type === "trade") return "Shared a trade"
  if (row.type === "post" || row.type === "profile_post") return "Shared a post"
  return "New message"
}

export async function updateConversationPreview(
  supabase: SupabaseClient,
  conversationId: string,
  lastMessage: string,
  lastMessageAt?: string
): Promise<string> {
  const at = lastMessageAt ?? new Date().toISOString()
  const { error } = await supabase
    .from("conversations")
    .update({
      last_message: lastMessage,
      last_message_at: at,
    })
    .eq("id", conversationId)

  if (error) {
    console.error("[conversationInboxSync] updateConversationPreview:", error)
  }
  return at
}

function persistInboxPatch(patch: ConversationInboxPatch): boolean {
  if (typeof window === "undefined") return false
  try {
    const patches = readInboxPatches()
    const existing = patches[patch.conversationId]
    if (
      existing &&
      !isIncomingInboxTimestampNewerOrEqual(
        patch.last_message_at,
        existing.last_message_at
      )
    ) {
      return false
    }
    patches[patch.conversationId] = patch
    sessionStorage.setItem(INBOX_PATCHES_STORAGE_KEY, JSON.stringify(patches))
    return true
  } catch {
    /* ignore quota / private mode */
    return false
  }
}

export function readInboxPatches(): Record<string, ConversationInboxPatch> {
  if (typeof window === "undefined") return {}
  try {
    const raw = sessionStorage.getItem(INBOX_PATCHES_STORAGE_KEY)
    if (!raw) return {}
    const parsed = JSON.parse(raw) as Record<string, ConversationInboxPatch>
    return parsed && typeof parsed === "object" ? parsed : {}
  } catch {
    return {}
  }
}

export function clearInboxPatch(conversationId: string) {
  if (typeof window === "undefined") return
  try {
    const patches = readInboxPatches()
    if (!patches[conversationId]) return
    delete patches[conversationId]
    sessionStorage.setItem(INBOX_PATCHES_STORAGE_KEY, JSON.stringify(patches))
  } catch {
    /* ignore */
  }
}

/** Notify inbox list (mounted or later via sessionStorage patches). */
export function dispatchConversationInboxPatch(patch: ConversationInboxPatch) {
  if (!persistInboxPatch(patch)) return
  if (typeof window === "undefined") return
  window.dispatchEvent(
    new CustomEvent(CONVERSATION_UPDATED_EVENT, { detail: patch })
  )
}

export function applyInboxPatchesToConversations<
  T extends {
    id: string
    lastMessage?: string
    last_message_at?: string | null
  },
>(list: T[], patches?: Record<string, ConversationInboxPatch>): T[] {
  const map = patches ?? readInboxPatches()
  if (Object.keys(map).length === 0) return list

  return list.map((c) => {
    const patch = map[String(c.id)]
    if (!patch) return c
    return mergeConversationInboxFields(c, {
      last_message: patch.last_message,
      last_message_at: patch.last_message_at,
    })
  })
}
