"use client"

import { ConnectionState } from "livekit-client"
import { useSyncExternalStore } from "react"
import type { LiveVoiceStableSnapshot } from "@/lib/livekit/client/tradeRoomLiveVoiceStore.ts"
import {
  getTradeRoomLiveVoiceDiagnostics,
  getTradeRoomLiveVoiceParticipantsSnapshot,
  getTradeRoomLiveVoiceStableSnapshot,
  joinTradeRoomLiveVoice,
  leaveTradeRoomLiveVoice,
  resumeTradeRoomLiveVoicePlayback,
  setTradeRoomLiveVoiceMuted,
  subscribeTradeRoomLiveVoiceParticipants,
  subscribeTradeRoomLiveVoiceStable,
} from "@/lib/livekit/client/tradeRoomLiveVoiceStore.ts"

/**
 * Full General Voice snapshot: connection state + participants (speaking/muted).
 * Use only in floating voice UI (`TradeRoomLiveVoiceBar`). Subscribes to
 * `ActiveSpeakersChanged` via participant channel.
 */
export function useTradeRoomLiveVoice() {
  const stable = useSyncExternalStore(
    subscribeTradeRoomLiveVoiceStable,
    getTradeRoomLiveVoiceStableSnapshot,
    getTradeRoomLiveVoiceStableSnapshot
  )
  const { participants } = useSyncExternalStore(
    subscribeTradeRoomLiveVoiceParticipants,
    getTradeRoomLiveVoiceParticipantsSnapshot,
    getTradeRoomLiveVoiceParticipantsSnapshot
  )

  return {
    ...stable,
    participants,
    join: joinTradeRoomLiveVoice,
    leave: leaveTradeRoomLiveVoice,
    resumePlayback: resumeTradeRoomLiveVoicePlayback,
    setMuted: setTradeRoomLiveVoiceMuted,
    diagnostics:
      process.env.NODE_ENV === "production"
        ? null
        : getTradeRoomLiveVoiceDiagnostics(),
    isConnected:
      stable.session != null &&
      stable.connectionState === ConnectionState.Connected,
  }
}

type TradeRoomLiveVoiceStableConnection = LiveVoiceStableSnapshot & {
  join: typeof joinTradeRoomLiveVoice
  leave: typeof leaveTradeRoomLiveVoice
  resumePlayback: typeof resumeTradeRoomLiveVoicePlayback
  setMuted: typeof setTradeRoomLiveVoiceMuted
  isConnected: boolean
}

/**
 * Connection/session/busy/error only — **does not** re-render when someone
 * speaks (active speaker). Use on Trade Room page for composer gating, sidebar,
 * join buttons, etc.
 */
export function useTradeRoomLiveVoiceStableConnection(): TradeRoomLiveVoiceStableConnection {
  const stable = useSyncExternalStore(
    subscribeTradeRoomLiveVoiceStable,
    getTradeRoomLiveVoiceStableSnapshot,
    getTradeRoomLiveVoiceStableSnapshot
  )

  return {
    ...stable,
    join: joinTradeRoomLiveVoice,
    leave: leaveTradeRoomLiveVoice,
    resumePlayback: resumeTradeRoomLiveVoicePlayback,
    setMuted: setTradeRoomLiveVoiceMuted,
    isConnected:
      stable.session != null &&
      stable.connectionState === ConnectionState.Connected,
  }
}
