import type {
  RealtimePostgresChangesPayload,
  SupabaseClient,
} from "@supabase/supabase-js"
import {
  attachRoomRealtimePresence,
  type RoomPresenceUser,
} from "./roomRealtimePresence.ts"
import { isBackendV2Enabled } from "./backendV2/flags.ts"
import type { RoomMessageReactionRow } from "./roomMessageReactions.ts"

export type { RoomMessageReactionRow }

export type RoomReactionChangeHandler = (payload: {
  eventType: string
  row: RoomMessageReactionRow
}) => void

export type RoomMessageInsertHandler = (payload: {
  id: string
  new: Record<string, unknown>
}) => void

export type RoomLiveChannelOptions = {
  supabase: SupabaseClient
  roomId: string
  onMessageInsert: RoomMessageInsertHandler
  onReactionChange: RoomReactionChangeHandler
  /** Client gate — ignore reactions for messages not currently loaded. */
  isMessageVisible: (messageId: string) => boolean
  /** When true, subscribe with room_id filter (requires migration). */
  useRoomScopedReactions?: boolean
  /** Optional Realtime Presence on the same channel. */
  presence?: {
    presenceKey: string
    userId: string
    username: string
    avatarUrl: string | null
    onActiveUsers: (users: RoomPresenceUser[]) => void
    onError?: (error: unknown) => void
  }
}

/**
 * Stable selected-room channel: messages + reactions (+ optional presence).
 * Does not depend on visible message IDs — no churn on scroll/section switch.
 */
export function subscribeCommunityRoomLiveChannel(
  options: RoomLiveChannelOptions
): () => void {
  const {
    supabase,
    roomId,
    onMessageInsert,
    onReactionChange,
    isMessageVisible,
    useRoomScopedReactions = true,
    presence,
  } = options

  const channel = presence
    ? supabase.channel(`room-live-${roomId}`, {
        config: {
          presence: {
            key: presence.presenceKey,
            enabled: true,
          },
        },
      })
    : supabase.channel(`room-live-${roomId}`)

  channel.on(
    "postgres_changes",
    {
      event: "INSERT",
      schema: "public",
      table: "room_messages",
      filter: `room_id=eq.${roomId}`,
    },
    (payload: RealtimePostgresChangesPayload<Record<string, unknown>>) => {
      const id = (payload.new as { id?: string })?.id
      if (!id) return
      onMessageInsert({ id, new: payload.new as Record<string, unknown> })
    }
  )

  if (useRoomScopedReactions) {
    channel.on(
      "postgres_changes",
      {
        event: "*",
        schema: "public",
        table: "room_message_reactions",
        filter: `room_id=eq.${roomId}`,
      },
      (payload: RealtimePostgresChangesPayload<RoomMessageReactionRow>) => {
        const eventType = payload.eventType
        const row = (payload.new ?? payload.old) as
          | RoomMessageReactionRow
          | undefined
        if (!row?.message_id || !isMessageVisible(row.message_id)) return

        if (eventType === "INSERT" && payload.new) {
          onReactionChange({
            eventType,
            row: payload.new as RoomMessageReactionRow,
          })
          return
        }
        if (eventType === "DELETE" && payload.old) {
          onReactionChange({
            eventType,
            row: payload.old as RoomMessageReactionRow,
          })
        }
      }
    )
  }

  const presenceAttach = presence
    ? attachRoomRealtimePresence(channel, {
        presenceKey: presence.presenceKey,
        userId: presence.userId,
        username: presence.username,
        avatarUrl: presence.avatarUrl,
        onActiveUsers: presence.onActiveUsers,
        onError: presence.onError,
      })
    : null

  channel.subscribe(async (status) => {
    if (status === "SUBSCRIBED" && presenceAttach) {
      await presenceAttach.trackOnce()
    }
  })

  return () => {
    void presenceAttach?.untrack()
    void supabase.removeChannel(channel)
  }
}

export function isRoomScopedReactionRealtimeEnabled(): boolean {
  return isBackendV2Enabled("rooms")
}
