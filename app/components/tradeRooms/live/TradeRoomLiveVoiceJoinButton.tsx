"use client"

import { Headphones } from "lucide-react"
import { isVoiceLiveSection } from "@/lib/livekit/client/liveVoiceSection.ts"
import { useTradeRoomLiveVoice } from "./useTradeRoomLiveVoice.ts"

type Props = {
  roomId: string | null
  section: {
    id: string
    name?: string | null
    live_kind?: string | null
  } | null
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
  section,
  roomName,
  disabled,
  fetchToken,
}: Props) {
  const voice = useTradeRoomLiveVoice()

  if (!roomId || !section || !isVoiceLiveSection(section.live_kind)) {
    return null
  }

  const inThisChannel =
    voice.session?.roomId === roomId && voice.session?.sectionId === section.id

  if (inThisChannel && voice.isConnected) {
    return (
      <span className="inline-flex items-center gap-1 rounded-full bg-emerald-500/15 px-2 py-0.5 text-xs text-emerald-200">
        <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-emerald-400" />
        In voice
      </span>
    )
  }

  return (
    <button
      type="button"
      disabled={disabled || voice.isBusy}
      onClick={() =>
        void voice.join({
          roomId,
          sectionId: section.id,
          roomLabel: roomName?.trim() || "Trade Room",
          channelLabel: section.name?.trim() || "Voice",
          fetchToken,
        })
      }
      className="inline-flex items-center gap-1.5 rounded-lg bg-emerald-600/90 px-3 py-1.5 text-xs font-medium text-white hover:bg-emerald-500 disabled:cursor-not-allowed disabled:opacity-50"
    >
      <Headphones className="h-3.5 w-3.5" />
      {voice.isBusy ? "Joining…" : "Join voice"}
    </button>
  )
}
