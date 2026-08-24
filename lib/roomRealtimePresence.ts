import type { RealtimeChannel } from "@supabase/supabase-js"
import { isBackendV2Enabled } from "./backendV2/flags.ts"

export type RoomPresenceUser = {
  user_id: string
  username: string
  avatar_url: string | null
  entered_at: string
}

export type RoomPresenceAttachOptions = {
  presenceKey: string
  userId: string
  username: string
  avatarUrl: string | null
  onActiveUsers: (users: RoomPresenceUser[]) => void
  onError?: (error: unknown) => void
}

function dedupePresenceByUserId(
  state: Record<string, RoomPresenceUser[]>
): RoomPresenceUser[] {
  const byUser = new Map<string, RoomPresenceUser>()
  for (const presences of Object.values(state)) {
    for (const row of presences) {
      if (!row?.user_id) continue
      const existing = byUser.get(row.user_id)
      if (
        !existing ||
        String(row.entered_at ?? "") > String(existing.entered_at ?? "")
      ) {
        byUser.set(row.user_id, row)
      }
    }
  }
  return Array.from(byUser.values())
}

/** Register presence listeners; call `trackOnce()` after channel SUBSCRIBED. */
export function attachRoomRealtimePresence(
  channel: RealtimeChannel,
  options: RoomPresenceAttachOptions
): { trackOnce: () => Promise<void>; untrack: () => Promise<void> } {
  const { userId, username, avatarUrl, onActiveUsers, onError } = options

  let stopped = false
  let tracked = false

  const emitSync = () => {
    if (stopped) return
    const state = channel.presenceState<RoomPresenceUser>()
    onActiveUsers(dedupePresenceByUserId(state))
  }

  channel
    .on("presence", { event: "sync" }, emitSync)
    .on("presence", { event: "join" }, emitSync)
    .on("presence", { event: "leave" }, emitSync)

  const trackOnce = async () => {
    if (stopped || tracked) return
    tracked = true
    try {
      await channel.track({
        user_id: userId,
        username,
        avatar_url: avatarUrl,
        entered_at: new Date().toISOString(),
      })
      emitSync()
    } catch (error) {
      onError?.(error)
    }
  }

  const untrack = async () => {
    stopped = true
    if (!tracked) return
    try {
      await channel.untrack()
    } catch (error) {
      onError?.(error)
    }
  }

  return { trackOnce, untrack }
}

export function isRoomRealtimePresenceEnabled(): boolean {
  return isBackendV2Enabled("roomPresence")
}

export const ROOM_PRESENCE_SEMANTIC_NOTE =
  "REST presence expires ~135s after last heartbeat; Realtime Presence reflects live channel membership."

export { dedupePresenceByUserId }
