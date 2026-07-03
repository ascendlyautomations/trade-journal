import type { RealtimeChannel } from "@supabase/supabase-js"
import { isDemoSupabaseBlocked } from "@/lib/demo/demoSupabaseGuard"
import { supabase } from "@/lib/supabaseClient"

export type NotificationChangePayload = {
  eventType: string
  new: Record<string, unknown> | null
  old: { id?: string } | null
}

type Listener = (payload: NotificationChangePayload) => void

type SharedChannel = {
  channel: RealtimeChannel
  listeners: Set<Listener>
}

const sharedByUser = new Map<string, SharedChannel>()

function dispatch(userId: string, payload: NotificationChangePayload) {
  sharedByUser.get(userId)?.listeners.forEach((listener) => {
    listener(payload)
  })
}

/** One Supabase channel per user — shared by Navbar badge and notifications inbox. */
export function subscribeNotificationChanges(
  userId: string,
  listener: Listener
): () => void {
  if (!userId || isDemoSupabaseBlocked()) return () => {}

  let entry = sharedByUser.get(userId)
  if (!entry) {
    const channel = supabase.channel(`notif-shared-${userId}`)
    channel.on(
      "postgres_changes",
      {
        event: "*",
        schema: "public",
        table: "notifications",
        filter: `user_id=eq.${userId}`,
      },
      (payload: {
        eventType: string
        new?: Record<string, unknown>
        old?: { id?: string }
      }) => {
        dispatch(userId, {
          eventType: payload.eventType,
          new: payload.new ?? null,
          old: payload.old ?? null,
        })
      }
    )
    channel.subscribe()
    entry = { channel, listeners: new Set() }
    sharedByUser.set(userId, entry)
  }

  entry.listeners.add(listener)
  return () => {
    const current = sharedByUser.get(userId)
    if (!current) return
    current.listeners.delete(listener)
    if (current.listeners.size === 0) {
      void supabase.removeChannel(current.channel)
      sharedByUser.delete(userId)
    }
  }
}

export function resetNotificationRealtimeSession() {
  for (const entry of sharedByUser.values()) {
    void supabase.removeChannel(entry.channel)
  }
  sharedByUser.clear()
}
