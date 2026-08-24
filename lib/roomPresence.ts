import type { SupabaseClient } from "@supabase/supabase-js"
import { asJsonObject, mapProjectedRows } from "./supabaseProjectedQuery.ts"

export const ROOM_PRESENCE_HEARTBEAT_MS = 60_000
export const ROOM_PRESENCE_ACTIVE_THRESHOLD_MS = 135_000

export type RoomActivePresence = {
  user_id: string
  profiles?: {
    id: string
    username: string
    avatar_url: string | null
  } | null
}

export async function upsertRoomPresenceHeartbeat(
  supabase: SupabaseClient,
  roomId: string,
  userId: string
): Promise<void> {
  const { error } = await supabase.from("room_presence").upsert(
    {
      room_id: roomId,
      user_id: userId,
      last_seen: new Date().toISOString(),
    },
    { onConflict: "room_id,user_id" }
  )

  if (error) throw error
}

export async function deleteRoomPresence(
  supabase: SupabaseClient,
  roomId: string,
  userId: string
): Promise<void> {
  const { error } = await supabase
    .from("room_presence")
    .delete()
    .eq("room_id", roomId)
    .eq("user_id", userId)

  if (error) throw error
}

export async function fetchActiveRoomPresence(
  supabase: SupabaseClient,
  roomId: string
): Promise<RoomActivePresence[]> {
  const threshold = new Date(
    Date.now() - ROOM_PRESENCE_ACTIVE_THRESHOLD_MS
  ).toISOString()

  const { data, error } = await supabase
    .from("room_presence")
    .select(
      `
      user_id,
      profiles (
        id,
        username,
        avatar_url
      )
    `
    )
    .eq("room_id", roomId)
    .gt("last_seen", threshold)

  if (error) throw error

  return Array.from(
    new Map(
      mapProjectedRows(data, (row): RoomActivePresence => {
        const profilesRaw = row.profiles
        const profileRow = asJsonObject(
          Array.isArray(profilesRaw) ? profilesRaw[0] : profilesRaw
        )
        return {
          user_id: String(row.user_id ?? ""),
          profiles: profileRow
            ? {
                id: String(profileRow.id ?? ""),
                username: String(profileRow.username ?? ""),
                avatar_url:
                  profileRow.avatar_url != null
                    ? String(profileRow.avatar_url)
                    : null,
              }
            : null,
        }
      }).map((row) => [row.user_id, row])
    ).values()
  )
}

export type RoomPresenceSession = {
  stop: () => Promise<void>
}

/**
 * Heartbeat + active-user polling for a single room. Call `stop()` on leave,
 * room switch, and unmount before revoking membership so RLS never rejects
 * in-flight upserts.
 */
export function createRoomPresenceSession(
  supabase: SupabaseClient,
  options: {
    roomId: string
    userId: string
    onActiveUsers: (users: RoomActivePresence[]) => void
    onError?: (error: unknown) => void
    heartbeatMs?: number
  }
): RoomPresenceSession {
  const { roomId, userId, onActiveUsers, onError } = options
  const heartbeatMs = options.heartbeatMs ?? ROOM_PRESENCE_HEARTBEAT_MS

  let stopped = false
  let inFlight: Promise<void> | null = null
  let intervalId: ReturnType<typeof setInterval> | null = null
  const visibilityDocument =
    typeof document === "undefined" ? null : document

  const runTick = async () => {
    if (
      stopped ||
      inFlight ||
      visibilityDocument?.visibilityState === "hidden"
    ) {
      return
    }

    const task = (async () => {
      if (stopped) return

      const upsertTask = upsertRoomPresenceHeartbeat(supabase, roomId, userId).catch(
        (error) => {
          if (!stopped) onError?.(error)
        }
      )

      const readTask = fetchActiveRoomPresence(supabase, roomId)
        .then((users) => {
          if (stopped) return
          onActiveUsers(users)
        })
        .catch((error) => {
          if (!stopped) onError?.(error)
        })

      await Promise.allSettled([upsertTask, readTask])
    })()

    inFlight = task
    try {
      await task
    } catch (error) {
      if (!stopped) onError?.(error)
    } finally {
      if (inFlight === task) inFlight = null
    }
  }

  const stopInterval = () => {
    if (intervalId == null) return
    globalThis.clearInterval(intervalId)
    intervalId = null
  }

  const startInterval = () => {
    if (stopped || intervalId != null) return
    intervalId = globalThis.setInterval(() => {
      void runTick()
    }, heartbeatMs) as ReturnType<typeof setInterval>
  }

  const handleVisibilityChange = () => {
    if (visibilityDocument?.visibilityState === "hidden") {
      stopInterval()
      return
    }
    void runTick()
    startInterval()
  }

  if (visibilityDocument?.visibilityState !== "hidden") {
    void runTick()
    startInterval()
  }
  visibilityDocument?.addEventListener(
    "visibilitychange",
    handleVisibilityChange
  )

  const stop = async () => {
    if (stopped) return
    stopped = true

    stopInterval()
    visibilityDocument?.removeEventListener(
      "visibilitychange",
      handleVisibilityChange
    )

    if (inFlight) {
      try {
        await inFlight
      } catch {
        // In-flight tick may fail after membership revoked; still delete presence.
      }
    }

    try {
      await deleteRoomPresence(supabase, roomId, userId)
    } catch (error) {
      onError?.(error)
    }
  }

  return { stop }
}
