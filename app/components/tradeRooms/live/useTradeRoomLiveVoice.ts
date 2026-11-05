"use client"

import { ConnectionState } from "livekit-client"
import { useSyncExternalStore } from "react"
import {
  getTradeRoomLiveVoiceSnapshot,
  joinTradeRoomLiveVoice,
  leaveTradeRoomLiveVoice,
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
    setMuted: setTradeRoomLiveVoiceMuted,
    isConnected:
      snapshot.session != null &&
      snapshot.connectionState === ConnectionState.Connected,
  }
}
