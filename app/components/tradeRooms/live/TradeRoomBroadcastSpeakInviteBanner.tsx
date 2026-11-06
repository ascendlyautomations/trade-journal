"use client"

import { Mic } from "lucide-react"
import {
  acceptTradeRoomBroadcastSpeakInvite,
  dismissTradeRoomBroadcastSpeakInvite,
  getTradeRoomBroadcastViewerVideoElement,
} from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"
import { fetchBroadcastConversationJoinPayload } from "@/lib/livekit/client/tradeRoomBroadcastJoinConversation.ts"

type Props = {
  roomId: string
  accessToken: string
  busy?: boolean
  onNeedOpenStream?: () => void
}

export default function TradeRoomBroadcastSpeakInviteBanner({
  roomId,
  accessToken,
  busy,
  onNeedOpenStream,
}: Props) {
  const videoReady = Boolean(getTradeRoomBroadcastViewerVideoElement())

  return (
    <div className="mb-2 rounded-lg border border-emerald-400/40 bg-emerald-950/80 px-3 py-3 text-sm text-emerald-50 shadow-lg">
      <div className="flex items-start gap-2">
        <Mic className="mt-0.5 h-4 w-4 shrink-0 text-emerald-300" aria-hidden />
        <div className="min-w-0 flex-1">
          <p className="font-semibold">You&apos;ve been invited to speak</p>
          <p className="mt-1 text-xs text-emerald-100/90">
            {videoReady
              ? "Connecting you with microphone access… If nothing happens, tap Accept below."
              : "Open the livestream first, then accept to use your microphone."}
          </p>
          <div className="mt-3 flex flex-wrap gap-2">
            {!videoReady && onNeedOpenStream ? (
              <button
                type="button"
                className="rounded-lg bg-white/15 px-3 py-1.5 text-xs font-semibold text-emerald-50"
                onClick={onNeedOpenStream}
              >
                Open stream
              </button>
            ) : null}
            <button
              type="button"
              disabled={busy || !videoReady}
              className="rounded-lg bg-emerald-500 px-3 py-1.5 text-xs font-semibold text-black disabled:opacity-50"
              onClick={() => {
                const videoElement = getTradeRoomBroadcastViewerVideoElement()
                if (!videoElement) {
                  onNeedOpenStream?.()
                  return
                }
                void acceptTradeRoomBroadcastSpeakInvite({
                  roomId,
                  videoElement,
                  accessToken,
                  fetchConversationToken: () =>
                    fetchBroadcastConversationJoinPayload(accessToken, roomId),
                })
              }}
            >
              Accept &amp; speak
            </button>
            <button
              type="button"
              className="rounded-lg border border-white/20 px-3 py-1.5 text-xs text-emerald-100"
              onClick={() => dismissTradeRoomBroadcastSpeakInvite()}
            >
              Not now
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
