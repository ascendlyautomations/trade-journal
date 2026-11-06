"use client"

import { ConnectionState } from "livekit-client"
import { useSyncExternalStore } from "react"
import {
  getTradeRoomLiveVoiceDiagnostics,
  getTradeRoomLiveVoiceSnapshot,
  joinTradeRoomLiveVoice,
  leaveTradeRoomLiveVoice,
  resumeTradeRoomLiveVoicePlayback,
  setTradeRoomLiveVoiceMuted,
  subscribeTradeRoomLiveVoice,
} from "@/lib/livekit/client/tradeRoomLiveVoiceStore.ts"

export function useTradeRoomLiveVoice() {
  const snapshot = useSyncExternalStore(
    subscribeTradeRoomLiveVoice,
    getTradeRoomLiveVoiceSnapshot,
    getTradeRoomLiveVoiceSnapshot
  )

  return {
    ...snapshot,
    join: joinTradeRoomLiveVoice,
    leave: leaveTradeRoomLiveVoice,
    resumePlayback: resumeTradeRoomLiveVoicePlayback,
    setMuted: setTradeRoomLiveVoiceMuted,
    diagnostics:
      process.env.NODE_ENV === "production"
        ? null
        : getTradeRoomLiveVoiceDiagnostics(),
    isConnected:
      snapshot.session != null &&
      snapshot.connectionState === ConnectionState.Connected,
  }
}
