"use client"

import { Video, VideoOff } from "lucide-react"
import { useTradeRoomBroadcast } from "./useTradeRoomBroadcast.ts"
import {
  setTradeRoomBroadcastScreenCameraOverlayEnabled,
  setTradeRoomBroadcastScreenCameraOverlayPosition,
  setTradeRoomBroadcastScreenOverlayCameraVisible,
  tradeRoomBroadcastScreenOverlayAvailable,
} from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"
import type { ScreenCameraOverlayPosition } from "@/lib/livekit/client/tradeRoomBroadcastScreenOverlayTypes.ts"
import { SCREEN_CAMERA_OVERLAY_POSITIONS } from "@/lib/livekit/client/tradeRoomBroadcastScreenOverlayTypes.ts"

const POSITION_LABEL: Record<ScreenCameraOverlayPosition, string> = {
  "top-left": "TL",
  "top-right": "TR",
  "bottom-left": "BL",
  "bottom-right": "BR",
}

type Props = {
  className?: string
  compact?: boolean
}

export default function TradeRoomBroadcastScreenOverlayControls({
  className = "",
  compact = false,
}: Props) {
  const broadcast = useTradeRoomBroadcast()
  const available = tradeRoomBroadcastScreenOverlayAvailable(broadcast)
  if (!available) return null

  const busy = broadcast.screenCameraOverlayBusy || broadcast.isBusy
  const overlayOn = broadcast.screenCameraOverlayEnabled
  const camOn =
    overlayOn && broadcast.screenCameraOverlayCameraVisible

  return (
    <div
      className={`flex flex-wrap items-center gap-2 rounded-lg border border-white/10 bg-black/30 px-2 py-1.5 text-xs ${className}`}
    >
      <span className="font-medium text-white/80">Camera overlay</span>
      <button
        type="button"
        disabled={busy}
        onClick={() =>
          void setTradeRoomBroadcastScreenCameraOverlayEnabled(!overlayOn)
        }
        className={`rounded-md px-2 py-1 font-semibold ${
          overlayOn
            ? "bg-emerald-600/90 text-white"
            : "bg-white/10 text-gray-200 hover:bg-white/15"
        } disabled:opacity-50`}
      >
        {overlayOn ? "On" : "Off"}
      </button>
      {overlayOn ? (
        <>
          <button
            type="button"
            disabled={busy}
            title={camOn ? "Hide webcam PiP" : "Show webcam PiP"}
            onClick={() =>
              void setTradeRoomBroadcastScreenOverlayCameraVisible(!camOn)
            }
            className="inline-flex items-center gap-1 rounded-md border border-white/15 px-2 py-1 text-gray-100 disabled:opacity-50"
          >
            {camOn ? <Video size={14} /> : <VideoOff size={14} />}
            {compact ? null : <span>{camOn ? "Camera" : "No cam"}</span>}
          </button>
          <span className="hidden text-white/50 sm:inline">Position</span>
          <div className="flex gap-0.5">
            {SCREEN_CAMERA_OVERLAY_POSITIONS.map((pos) => (
              <button
                key={pos}
                type="button"
                disabled={busy}
                title={pos.replace("-", " ")}
                onClick={() =>
                  void setTradeRoomBroadcastScreenCameraOverlayPosition(pos)
                }
                className={`min-w-[2rem] rounded px-1 py-0.5 font-mono text-[10px] disabled:opacity-50 ${
                  broadcast.screenCameraOverlayPosition === pos
                    ? "bg-white/20 text-white"
                    : "text-gray-400 hover:bg-white/10"
                }`}
              >
                {POSITION_LABEL[pos]}
              </button>
            ))}
          </div>
        </>
      ) : null}
      {broadcast.screenCameraOverlayError ? (
        <span className="text-amber-300">{broadcast.screenCameraOverlayError}</span>
      ) : null}
    </div>
  )
}
