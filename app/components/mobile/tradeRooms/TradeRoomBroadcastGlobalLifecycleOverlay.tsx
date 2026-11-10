"use client"

import { useCallback, useState } from "react"
import { useRouter } from "next/navigation"
import { WifiOff } from "lucide-react"
import { useTradeRoomBroadcast } from "@/app/components/tradeRooms/live/useTradeRoomBroadcast.ts"
import {
  acknowledgeTradeRoomBroadcastStreamEnded,
  acknowledgeTradeRoomBroadcastViewerRemoval,
  acknowledgeViewerBroadcastConnectionLost,
  presentTradeRoomBroadcastStreamEndedNotice,
} from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"
import { BroadcastNoActiveStreamError } from "@/lib/livekit/client/tradeRoomBroadcastErrors.ts"
import { openTradeRoomBroadcastViewerStudio } from "@/lib/livekit/client/tradeRoomBroadcastStudioNavigation.ts"
import { usePhoneWebTouchTarget } from "@/lib/usePhoneWebTouchTarget"

type Props = {
  accessToken: string | null
}

export default function TradeRoomBroadcastGlobalLifecycleOverlay({
  accessToken,
}: Props) {
  const phoneWeb = usePhoneWebTouchTarget()
  const router = useRouter()
  const broadcast = useTradeRoomBroadcast()
  const [reconnectBusy, setReconnectBusy] = useState(false)

  const removal = broadcast.viewerStreamRemovalNotice
  const connectionLost = broadcast.viewerBroadcastConnectionLost
  const streamEnded = broadcast.viewerStreamEndedNotice

  const onRetryConnection = useCallback(async () => {
    if (!connectionLost || !accessToken || reconnectBusy) return
    const { roomId, sessionId } = connectionLost
    setReconnectBusy(true)
    acknowledgeViewerBroadcastConnectionLost()
    try {
      await openTradeRoomBroadcastViewerStudio({
        roomId,
        accessToken,
        viewerUserId: broadcast.viewerUserId,
      })
    } catch (err) {
      if (err instanceof BroadcastNoActiveStreamError) {
        presentTradeRoomBroadcastStreamEndedNotice(sessionId)
      }
    } finally {
      setReconnectBusy(false)
    }
  }, [
    accessToken,
    broadcast.viewerUserId,
    connectionLost,
    reconnectBusy,
  ])

  const onOpenRoomAfterRemoval = useCallback(() => {
    acknowledgeTradeRoomBroadcastViewerRemoval()
    router.replace("/community")
  }, [router])

  if (!phoneWeb) return null

  if (removal) {
    const title =
      removal.kind === "banned" ? "Removed & blocked" : "Removed from stream"
    const body =
      removal.kind === "banned"
        ? "The host removed you from this livestream and blocked you from rejoining this session."
        : "The host removed you from this livestream."

    return (
      <div className="fixed inset-0 z-[10070] flex items-center justify-center bg-black/70 p-4 md:hidden">
        <div
          className="w-full max-w-sm rounded-2xl border border-white/10 bg-zinc-900 p-5 text-white shadow-2xl"
          role="alertdialog"
          aria-labelledby="broadcast-lifecycle-removal-title"
          aria-describedby="broadcast-lifecycle-removal-body"
        >
          <h2
            id="broadcast-lifecycle-removal-title"
            className="text-lg font-semibold"
          >
            {title}
          </h2>
          <p id="broadcast-lifecycle-removal-body" className="mt-2 text-sm text-white/75">
            {body}
          </p>
          <button
            type="button"
            className="mt-5 w-full rounded-xl bg-emerald-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-emerald-500"
            onClick={onOpenRoomAfterRemoval}
          >
            OK
          </button>
        </div>
      </div>
    )
  }

  if (connectionLost) {
    return (
      <div className="fixed inset-0 z-[10070] flex items-center justify-center bg-black/55 p-4 md:hidden">
        <div
          className="w-full max-w-sm rounded-2xl border border-white/10 bg-zinc-900 p-6 text-center text-white shadow-2xl"
          role="alertdialog"
          aria-labelledby="broadcast-lifecycle-connection-title"
        >
          <WifiOff
            className="mx-auto h-10 w-10 text-amber-400"
            aria-hidden
          />
          <h2
            id="broadcast-lifecycle-connection-title"
            className="mt-3 text-lg font-bold"
          >
            Connection lost
          </h2>
          <p className="mt-2 text-sm text-white/70">
            We lost the connection to this livestream. You can try again.
          </p>
          <div className="mt-5 space-y-2">
            <button
              type="button"
              disabled={!accessToken || reconnectBusy}
              className="w-full rounded-xl bg-emerald-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-emerald-500 disabled:opacity-50"
              onClick={() => void onRetryConnection()}
            >
              {reconnectBusy ? "Reconnecting…" : "Retry"}
            </button>
            <button
              type="button"
              className="w-full rounded-xl border border-white/15 px-4 py-2.5 text-sm font-semibold text-white/90 hover:bg-white/5"
              onClick={() => acknowledgeViewerBroadcastConnectionLost()}
            >
              Close
            </button>
          </div>
        </div>
      </div>
    )
  }

  if (streamEnded) {
    const title = streamEnded.roomTitle?.trim() || "Trade Room"
    return (
      <div className="fixed inset-0 z-[10070] flex items-center justify-center bg-black/55 p-4 md:hidden">
        <div
          className="w-full max-w-sm rounded-2xl border border-white/10 bg-zinc-900 p-6 text-center text-white shadow-2xl"
          role="alertdialog"
          aria-labelledby="broadcast-lifecycle-ended-title"
        >
          <div
            className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-emerald-600/20 text-lg font-bold text-emerald-300"
            aria-hidden
          >
            TT
          </div>
          <h2
            id="broadcast-lifecycle-ended-title"
            className="mt-3 text-lg font-bold"
          >
            Stream ended
          </h2>
          <p className="mt-2 text-sm text-white/70">
            The livestream in {title} has ended.
          </p>
          <button
            type="button"
            className="mt-5 w-full rounded-xl bg-emerald-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-emerald-500"
            onClick={() => acknowledgeTradeRoomBroadcastStreamEnded()}
          >
            Close
          </button>
        </div>
      </div>
    )
  }

  return null
}
