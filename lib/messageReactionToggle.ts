import type { SupabaseClient } from "@supabase/supabase-js"
import type {
  MessageReactionEmoji,
  MessageReactionRow,
} from "@/lib/roomMessageReactions"

export type MessageReactionPatch = (
  messageId: string,
  row: MessageReactionRow,
  mode: "insert" | "delete"
) => void

type ToggleMessageReactionBase = {
  supabase: SupabaseClient
  messageId: string
  reaction: MessageReactionEmoji
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
 * Optimistic add / remove / replace — matches native MessageReactionToggleCoordinator.
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

  const busyKey = `${messageId}::${reaction}`
  if (busyKeys.has(busyKey)) return
  busyKeys.add(busyKey)

  const viewerRows = findViewerReactions()
  const existingSame = viewerRows.find((row) => row.reaction === reaction)
  const priorViewerRows = viewerRows

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

    for (const row of priorViewerRows) {
      patch(messageId, row, "delete")
    }

    const optimistic: MessageReactionRow = {
      id: `optimistic-${messageId}-${reaction}`,
      message_id: messageId,
      user_id: viewerUserId,
      reaction,
    }
    patch(messageId, optimistic, "insert")

    for (const row of priorViewerRows) {
      if (row.id.startsWith("optimistic-")) continue
      const { error: deleteError } = await supabase
        .from(
          input.surface === "dm" ? "message_reactions" : "room_message_reactions"
        )
        .delete()
        .eq("id", row.id)
      if (deleteError) throw deleteError
    }

    if (input.surface === "dm") {
      const { data, error } = await supabase
        .from("message_reactions")
        .insert({
          message_id: messageId,
          user_id: viewerUserId,
          reaction,
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
        reaction,
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
      patch(
        messageId,
        {
          id: `optimistic-${messageId}-${reaction}`,
          message_id: messageId,
          user_id: viewerUserId,
          reaction,
        },
        "delete"
      )
      for (const row of priorViewerRows) {
        patch(messageId, row, "insert")
      }
    }
    onError?.("Could not update reaction. Please try again.")
  } finally {
    busyKeys.delete(busyKey)
  }
}
