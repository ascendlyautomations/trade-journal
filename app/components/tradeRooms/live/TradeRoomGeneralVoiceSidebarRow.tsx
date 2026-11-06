"use client"

import { Headphones } from "lucide-react"
import TradeRoomLiveVoiceJoinButton from "./TradeRoomLiveVoiceJoinButton.tsx"
import { TRADE_ROOM_VOICE_USER_LABEL } from "@/lib/livekit/tradeRoomSharedLiveVoice.ts"
import { useTradeRoomLiveVoice } from "./useTradeRoomLiveVoice.ts"

type Props = {
  roomId: string
  roomName: string | null
  disabled?: boolean
  fetchToken: () => Promise<{
    token: string
    livekitUrl: string
    canPublish: boolean
  }>
}

/** Sidebar row for the single shared voice channel per Trade Room. */
export default function TradeRoomGeneralVoiceSidebarRow({
  roomId,
  roomName,
  disabled,
  fetchToken,
}: Props) {
  const voice = useTradeRoomLiveVoice()
  const active =
    voice.session?.roomId === roomId &&
    (voice.isConnected || voice.isBusy)

  return (
    <div
      className={`mb-2 flex min-w-0 flex-col gap-1.5 rounded-lg border px-2 py-2 ${
        active
          ? "border-emerald-400/35 bg-emerald-500/10"
          : "border-white/10 bg-white/[0.03]"
      }`}
    >
      <div className="flex items-center gap-2 px-1">
        <Headphones className="h-4 w-4 shrink-0 text-emerald-400" aria-hidden />
        <span className="truncate text-sm font-medium text-emerald-100">
          {TRADE_ROOM_VOICE_USER_LABEL}
        </span>
      </div>
      <div className="px-1">
        <TradeRoomLiveVoiceJoinButton
          roomId={roomId}
          roomName={roomName}
          disabled={disabled}
          fetchToken={fetchToken}
        />
      </div>
    </div>
  )
}
