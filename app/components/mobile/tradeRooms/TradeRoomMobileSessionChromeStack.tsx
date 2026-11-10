"use client"

import { useMemo } from "react"
import TradeRoomBroadcastPersistentBar from "./TradeRoomBroadcastPersistentBar"
import TradeRoomLiveVoiceBar from "@/app/components/tradeRooms/live/TradeRoomLiveVoiceBar"
import { useTradeRoomBroadcast } from "@/app/components/tradeRooms/live/useTradeRoomBroadcast"
import { useTradeRoomLiveVoice } from "@/app/components/tradeRooms/live/useTradeRoomLiveVoice"
import { tradeRoomBroadcastGlobalChromeVisible } from "@/lib/livekit/client/tradeRoomBroadcastGlobalChromeVisibility.ts"

export type TradeRoomSessionChromePlacement = "shell" | "embedded"

type Props = {
  placement: TradeRoomSessionChromePlacement
  accessToken?: string | null
}

/**
 * Voice + livestream accessory stack — mirrors iOS `LiveVoiceTabShellLayout.bottomAccessory`.
 */
export default function TradeRoomMobileSessionChromeStack({
  placement,
  accessToken = null,
}: Props) {
  const voice = useTradeRoomLiveVoice()
  const broadcast = useTradeRoomBroadcast()

  const showVoice = useMemo(() => Boolean(voice.session?.roomId), [voice.session?.roomId])

  const showBroadcast = useMemo(() => {
    if (!tradeRoomBroadcastGlobalChromeVisible(broadcast)) return false
    if (broadcast.studioPresentation === "studio") return false
    return Boolean(broadcast.roomId?.trim())
  }, [broadcast])

  if (!showVoice && !showBroadcast) return null

  const voicePlacement = placement === "shell" ? "shell" : "embedded"

  return (
    <div
      className="flex w-full flex-col"
      data-tt-trade-room-session-chrome-stack
      data-placement={placement}
    >
      {showBroadcast ? (
        <TradeRoomBroadcastPersistentBar accessToken={accessToken} />
      ) : null}
      {showVoice ? <TradeRoomLiveVoiceBar placement={voicePlacement} /> : null}
    </div>
  )
}
