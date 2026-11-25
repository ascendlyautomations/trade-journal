import type { SupabaseClient } from "@supabase/supabase-js"
import type { MessageReactionRow } from "@/lib/roomMessageReactions"
import { normalizeMessageReaction } from "@/lib/messageReactionValidation"

export type MessageReactionPatch = (
  messageId: string,
  row: MessageReactionRow,
  mode: "insert" | "delete"
) => void

type ToggleMessageReactionBase = {
  supabase: SupabaseClient
  messageId: string
  reaction: string
  viewerUserId: string
  findViewerReactions: () => MessageReactionRow[]
  patch: MessageReactionPatch
  busyKeys: Set<string>
  onError?: (message: string) => void
}

export type ToggleDmMessageReactionInput = ToggleMessageReactionBase & {
  surface: "dm"
  conversationId: string
}

export type ToggleRoomMessageReactionInput = ToggleMessageReactionBase & {
  surface: "room"
  roomId: string
}

export type ToggleMessageReactionInput =
  | ToggleDmMessageReactionInput
  | ToggleRoomMessageReactionInput

/**
 * Optimistic toggle — one reaction per user per message.
 * Same emoji removes; a different emoji replaces the prior reaction.
 */
export async function toggleMessageReaction(
  input: ToggleMessageReactionInput
): Promise<void> {
  const {
    supabase,
    messageId,
    reaction,
    viewerUserId,
    findViewerReactions,
    patch,
    busyKeys,
    onError,
  } = input

  const emoji = normalizeMessageReaction(reaction)
  if (!emoji) return

  const busyKey = messageId
  if (busyKeys.has(busyKey)) return
  busyKeys.add(busyKey)

  const viewerRows = findViewerReactions()
  const existingSame = viewerRows.find(
    (row) => normalizeMessageReaction(row.reaction) === emoji
  )

  try {
    if (existingSame) {
      patch(messageId, existingSame, "delete")
      const { error } = await supabase
        .from(
          input.surface === "dm" ? "message_reactions" : "room_message_reactions"
        )
        .delete()
        .eq("id", existingSame.id)
      if (error) throw error
      return
    }

    for (const row of viewerRows) {
      patch(messageId, row, "delete")
    }

    const optimistic: MessageReactionRow = {
      id: `optimistic-${messageId}-${emoji}`,
      message_id: messageId,
      user_id: viewerUserId,
      reaction: emoji,
    }
    patch(messageId, optimistic, "insert")

    if (input.surface === "dm") {
      const { data, error } = await supabase
        .from("message_reactions")
        .insert({
          message_id: messageId,
          user_id: viewerUserId,
          reaction: emoji,
          conversation_id: input.conversationId,
        })
        .select("id, message_id, user_id, reaction, created_at")
        .single()
      if (error) throw error
      if (data) {
        patch(messageId, optimistic, "delete")
        patch(messageId, data as MessageReactionRow, "insert")
      }
      return
    }

    const { data, error } = await supabase
      .from("room_message_reactions")
      .insert({
        message_id: messageId,
        user_id: viewerUserId,
        reaction: emoji,
        room_id: input.roomId,
      })
      .select("id, message_id, user_id, reaction, created_at")
      .single()

    if (error) throw error

    if (data) {
      patch(messageId, optimistic, "delete")
      patch(messageId, data as MessageReactionRow, "insert")
    }
  } catch (error) {
    console.error("toggleMessageReaction:", error)
    if (existingSame) {
      patch(messageId, existingSame, "insert")
    } else {
      for (const row of viewerRows) {
        patch(messageId, row, "insert")
      }
      patch(
        messageId,
        {
          id: `optimistic-${messageId}-${emoji}`,
          message_id: messageId,
          user_id: viewerUserId,
          reaction: emoji,
        },
        "delete"
      )
    }
    onError?.("Could not update reaction. Please try again.")
  } finally {
    busyKeys.delete(busyKey)
  }
}