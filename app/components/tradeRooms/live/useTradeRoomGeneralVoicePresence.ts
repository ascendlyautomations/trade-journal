"use client"

import { useEffect, useRef, useState } from "react"
import { getSupabaseApiAccessToken } from "@/lib/supabaseBearerFetch"
import {
  generalVoicePresenceCache as presenceCache,
  generalVoicePresenceFetchByRoom as presenceFetchByRoom,
  PRESENCE_CACHE_MS,
  type GeneralVoicePresenceFetchResult as PresenceFetchResult,
  type GeneralVoicePresenceSnapshot as PresenceSnapshot,
} from "@/lib/livekit/client/generalVoicePresenceCache.ts"
import { useTradeRoomLiveVoiceStableConnection } from "./useTradeRoomLiveVoice.ts"

async function fetchGeneralVoicePresence(
  roomId: string,
  options?: { force?: boolean }
): Promise<PresenceFetchResult> {
  const cached = presenceCache.get(roomId)
  if (
    !options?.force &&
    cached &&
    Date.now() - cached.fetchedAt < PRESENCE_CACHE_MS
  ) {
    return { snapshot: cached }
  }

  const existing = presenceFetchByRoom.get(roomId)
  if (existing) {
    return existing
  }

  const pending = (async (): Promise<PresenceFetchResult> => {
    const accessToken = await getSupabaseApiAccessToken()
    if (!accessToken) {
      return { snapshot: presenceCache.get(roomId) ?? null, unauthorized: true }
    }

    const res = await fetch(
      `/api/livekit/voice/presence?roomId=${encodeURIComponent(roomId)}`,
      {
        headers: { Authorization: `Bearer ${accessToken}` },
      }
    )
    const stale = presenceCache.get(roomId) ?? null
    if (res.status === 401 || res.status === 403) {
      return { snapshot: stale, unauthorized: true }
    }
    if (!res.ok) return { snapshot: stale }
    const payload = (await res.json().catch(() => ({}))) as {
      connectedCount?: number
    }
    const snapshot: PresenceSnapshot = {
      connectedCount: Number(payload.connectedCount ?? 0),
      fetchedAt: Date.now(),
    }
    presenceCache.set(roomId, snapshot)
    return { snapshot }
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
  const authPausedRef = useRef(false)

  const inThisRoomVoice =
    Boolean(roomId) &&
    voice.session?.roomId === roomId &&
    voice.isConnected

  useEffect(() => {
    authPausedRef.current = false
  }, [roomId, accessToken])

  useEffect(() => {
    if (!enabled || !roomId || !accessToken || inThisRoomVoice) {
      return
    }

    let cancelled = false

    const applySnapshot = (snap: PresenceSnapshot | null) => {
      if (!cancelled && snap) setRemote(snap)
    }

    const load = (force: boolean) => {
      if (authPausedRef.current) return
      void fetchGeneralVoicePresence(
        roomId,
        force ? { force: true } : undefined
      ).then((result) => {
        if (result.unauthorized) authPausedRef.current = true
        applySnapshot(result.snapshot)
      })
    }

    load(false)

    const onVisibility = () => {
      if (document.visibilityState !== "visible") return
      if (authPausedRef.current) return
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
