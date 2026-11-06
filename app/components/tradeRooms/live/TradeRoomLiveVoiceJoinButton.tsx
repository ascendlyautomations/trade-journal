"use client"

import { Headphones } from "lucide-react"
import { useTradeRoomLiveVoice } from "./useTradeRoomLiveVoice.ts"

type Props = {
  roomId: string | null
  roomName: string | null
  disabled?: boolean
  fetchToken: () => Promise<{
    token: string
    livekitUrl: string
    canPublish: boolean
  }>
}

export default function TradeRoomLiveVoiceJoinButton({
  roomId,
  roomName,
  disabled,
  fetchToken,
}: Props) {
  const voice = useTradeRoomLiveVoice()

  if (!roomId) {
    return null
  }

  const inThisRoom =
    voice.session?.roomId === roomId && voice.isConnected

  if (inThisRoom) {
    return (
      <span className="inline-flex items-center gap-1 rounded-full bg-emerald-500/15 px-2 py-0.5 text-xs text-emerald-200">
        <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-emerald-400" />
        In voice
      </span>
    )
  }

  const joinError = voice.error && !voice.session ? voice.error : null

  return (
    <span className="inline-flex flex-col items-start gap-1">
      <button
        type="button"
        disabled={disabled || voice.isBusy}
        onClick={() => {
          void voice.join({
            roomId,
            roomLabel: roomName?.trim() || "Trade Room",
            fetchToken,
          })
        }}
        className="inline-flex items-center gap-1.5 rounded-lg bg-emerald-600/90 px-3 py-1.5 text-xs font-medium text-white hover:bg-emerald-500 disabled:cursor-not-allowed disabled:opacity-50"
      >
        <Headphones className="h-3.5 w-3.5" />
        {voice.isBusy ? "Joining…" : "Join Voice"}
      </button>
      {joinError ? (
        <span className="max-w-xs text-[11px] leading-snug text-red-300">
          {joinError}
        </span>
      ) : null}
    </span>
  )
}
