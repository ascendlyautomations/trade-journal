"use client"

import { useEffect } from "react"
import { leaveTradeRoomLiveVoice } from "@/lib/livekit/client/tradeRoomLiveVoiceStore.ts"

/** Disconnect live voice when auth session ends. */
export default function TradeRoomLiveVoiceSessionGuard({
  userId,
}: {
  userId: string | null | undefined
}) {
  useEffect(() => {
    if (!userId) {
      void leaveTradeRoomLiveVoice()
    }
  }, [userId])

  return null
}
