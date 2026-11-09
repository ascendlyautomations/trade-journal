"use client"

import { useEffect, useState } from "react"
import {
  generalVoicePresenceCache as presenceCache,
  generalVoicePresenceFetchByRoom as presenceFetchByRoom,
  PRESENCE_CACHE_MS,
  type GeneralVoicePresenceSnapshot as PresenceSnapshot,
} from "@/lib/livekit/client/generalVoicePresenceCache.ts"
import { useTradeRoomLiveVoiceStableConnection } from "./useTradeRoomLiveVoice.ts"

async function fetchGeneralVoicePresence(
  roomId: string,
  accessToken: string,
  options?: { force?: boolean }
): Promise<PresenceSnapshot | null> {
  const cached = presenceCache.get(roomId)
  if (
    !options?.force &&
    cached &&
    Date.now() - cached.fetchedAt < PRESENCE_CACHE_MS
  ) {
    return cached
  }

  const existing = presenceFetchByRoom.get(roomId)
  if (existing) {
    return existing
  }

  const pending = (async (): Promise<PresenceSnapshot | null> => {
    const res = await fetch(
      `/api/livekit/voice/presence?roomId=${encodeURIComponent(roomId)}`,
      {
        headers: { Authorization: `Bearer ${accessToken}` },
      }
    )
    const stale = presenceCache.get(roomId) ?? null
    if (!res.ok) return stale
    const payload = (await res.json().catch(() => ({}))) as {
      connectedCount?: number
    }
    const snapshot: PresenceSnapshot = {
      connectedCount: Number(payload.connectedCount ?? 0),
      fetchedAt: Date.now(),
    }
    presenceCache.set(roomId, snapshot)
    return snapshot
  })().finally(() => {
    presenceFetchByRoom.delete(roomId)
  })

  presenceFetchByRoom.set(roomId, pending)
  return pending
}

export function useTradeRoomGeneralVoicePresence(options: {
  roomId: string | null
  accessToken: string | null
  enabled?: boolean
}): {
  connectedCount: number | null
  isLiveFromClient: boolean
} {
  const { roomId, accessToken, enabled = true } = options
  const voice = useTradeRoomLiveVoiceStableConnection()
  const [remote, setRemote] = useState<PresenceSnapshot | null>(null)

  const inThisRoomVoice =
    Boolean(roomId) &&
    voice.session?.roomId === roomId &&
    voice.isConnected

  useEffect(() => {
    if (!enabled || !roomId || !accessToken || inThisRoomVoice) {
      return
    }

    let cancelled = false

    const applySnapshot = (snap: PresenceSnapshot | null) => {
      if (!cancelled && snap) setRemote(snap)
    }

    const load = (force: boolean) => {
      void fetchGeneralVoicePresence(roomId, accessToken, force ? { force: true } : undefined).then(
        (snap) => applySnapshot(snap)
      )
    }

    load(false)

    const onVisibility = () => {
      if (document.visibilityState !== "visible") return
      const cached = presenceCache.get(roomId)
      const stale =
        !cached || Date.now() - cached.fetchedAt >= PRESENCE_CACHE_MS
      if (stale) load(true)
    }

    document.addEventListener("visibilitychange", onVisibility)
    return () => {
      cancelled = true
      document.removeEventListener("visibilitychange", onVisibility)
    }
  }, [roomId, accessToken, enabled, inThisRoomVoice])

  if (inThisRoomVoice) {
    return {
      connectedCount: voice.participantCount,
      isLiveFromClient: true,
    }
  }

  return {
    connectedCount: remote?.connectedCount ?? null,
    isLiveFromClient: false,
  }
}
