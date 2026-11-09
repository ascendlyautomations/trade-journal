"use client"

import { Headphones } from "lucide-react"
import TradeRoomLiveVoiceJoinButton from "./TradeRoomLiveVoiceJoinButton.tsx"
import { formatGeneralVoicePresenceLabel } from "@/lib/livekit/client/formatGeneralVoicePresenceLabel.ts"
import { TRADE_ROOM_VOICE_USER_LABEL } from "@/lib/livekit/tradeRoomSharedLiveVoice.ts"
import { useTradeRoomLiveVoiceStableConnection } from "./useTradeRoomLiveVoice.ts"
import { useTradeRoomGeneralVoicePresence } from "./useTradeRoomGeneralVoicePresence.ts"

type Props = {
  roomId: string
  roomName: string | null
  accessToken?: string | null
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
  accessToken,
  disabled,
  fetchToken,
}: Props) {
  const voice = useTradeRoomLiveVoiceStableConnection()
  const presence = useTradeRoomGeneralVoicePresence({
    roomId,
    accessToken: accessToken ?? null,
    enabled: !disabled,
  })
  const presenceLabel = formatGeneralVoicePresenceLabel(presence.connectedCount)
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
        <div className="min-w-0 flex-1">
          <span className="block truncate text-sm font-medium text-emerald-100">
            {TRADE_ROOM_VOICE_USER_LABEL}
          </span>
          {presenceLabel ? (
            <span className="block truncate text-[11px] text-emerald-200/70">
              {presenceLabel}
            </span>
          ) : null}
        </div>
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
