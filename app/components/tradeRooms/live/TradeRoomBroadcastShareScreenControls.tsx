"use client"

import { Monitor, MonitorOff, MonitorUp } from "lucide-react"
import { useTradeRoomBroadcast } from "./useTradeRoomBroadcast.ts"
import {
  startTradeRoomBroadcastScreenShareWhileLive,
  stopTradeRoomBroadcastScreenShareWhileLive,
  switchTradeRoomBroadcastScreenShareSurface,
  tradeRoomBroadcastScreenShareProgramActive,
  tradeRoomBroadcastShareScreenWhileLiveAvailable,
} from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"

type Props = {
  className?: string
  compact?: boolean
}

export default function TradeRoomBroadcastShareScreenControls({
  className = "",
  compact = false,
}: Props) {
  const broadcast = useTradeRoomBroadcast()
  const canShare = tradeRoomBroadcastShareScreenWhileLiveAvailable(broadcast)
  const onScreenProgram = tradeRoomBroadcastScreenShareProgramActive(broadcast)

  if (!canShare && !onScreenProgram) return null

  const busy =
    broadcast.isBusy ||
    broadcast.screenShareWhileLiveBusy ||
    broadcast.screenCameraOverlayBusy

  return (
    <div
      className={`flex flex-wrap items-center gap-2 rounded-lg border border-white/10 bg-black/30 px-2 py-1.5 text-xs ${className}`}
    >
      {canShare ? (
        <button
          type="button"
          disabled={busy}
          title="Share your screen with webcam in the corner"
          onClick={() => void startTradeRoomBroadcastScreenShareWhileLive()}
          className="inline-flex items-center gap-1.5 rounded-md bg-sky-600/90 px-2.5 py-1 font-semibold text-white hover:bg-sky-500/90 disabled:opacity-50"
        >
          <Monitor size={14} />
          {compact ? "Share" : "Share screen"}
        </button>
      ) : null}
      {onScreenProgram ? (
        <>
          <button
            type="button"
            disabled={busy}
            title="Pick a different window, tab, or screen"
            onClick={() => void switchTradeRoomBroadcastScreenShareSurface()}
            className="inline-flex items-center gap-1.5 rounded-md border border-white/15 px-2 py-1 font-medium text-gray-100 hover:bg-white/10 disabled:opacity-50"
          >
            <MonitorUp size={14} />
            {compact ? "Change" : "Change share"}
          </button>
          <button
            type="button"
            disabled={busy}
            title="Stop sharing and return to full-screen webcam"
            onClick={() => void stopTradeRoomBroadcastScreenShareWhileLive()}
            className="inline-flex items-center gap-1.5 rounded-md border border-white/15 px-2 py-1 font-medium text-gray-100 hover:bg-white/10 disabled:opacity-50"
          >
            <MonitorOff size={14} />
            {compact ? "Webcam" : "Stop sharing"}
          </button>
        </>
      ) : null}
      {broadcast.screenShareWhileLiveError ? (
        <span className="text-amber-300">{broadcast.screenShareWhileLiveError}</span>
      ) : null}
    </div>
  )
}
