"use client"

import { Mic, MicOff, Volume2, VolumeX } from "lucide-react"
import { useEffect, useState } from "react"
import {
  setTradeRoomBroadcastStreamListenVolume,
  toggleTradeRoomBroadcastStreamListenMuted,
  toggleTradeRoomBroadcastViewerMicMuted,
} from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"
import { mediaElementVolumeIsAdjustable } from "@/lib/livekit/broadcastListenState.ts"

type ListenSnapshot = {
  streamListenMuted: boolean
  streamListenVolume: number
  isInConversation: boolean
  viewerMicMuted: boolean
  viewerMicPublishReady: boolean
}

function useBroadcastVolumeSliderSupported(): boolean {
  const [supported, setSupported] = useState(false)
  useEffect(() => {
    const probe = document.createElement("audio")
    setSupported(mediaElementVolumeIsAdjustable(probe))
  }, [])
  return supported
}

/** Incoming stream level and mute. Microphone mute is a separate button. */
export default function BroadcastListenControls({
  broadcast,
  tone = "studio",
}: {
  broadcast: ListenSnapshot
  tone?: "studio" | "mini" | "bar"
}) {
  const showSlider = useBroadcastVolumeSliderSupported()
  const percent = Math.round(broadcast.streamListenVolume * 100)
  const iconSize = 16
  const buttonClass =
    tone === "bar"
      ? "inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-[color:var(--chrome-foreground,#f3f4f6)] active:bg-white/10"
      : tone === "mini"
        ? "rounded-md border border-white/15 p-1 text-white"
        : "inline-flex items-center gap-2 rounded-lg border border-white/15 px-3 py-2 text-sm"

  return (
    <>
      <button
        type="button"
        aria-label={broadcast.streamListenMuted ? "Unmute stream" : "Mute stream"}
        className={buttonClass}
        onClick={() => toggleTradeRoomBroadcastStreamListenMuted()}
      >
        {broadcast.streamListenMuted ? (
          <VolumeX size={iconSize} aria-hidden />
        ) : (
          <Volume2 size={iconSize} aria-hidden />
        )}
        {tone === "studio" ? (broadcast.streamListenMuted ? "Muted" : "Sound on") : null}
      </button>
      {showSlider ? (
        <input
          type="range"
          min={0}
          max={100}
          step={1}
          value={percent}
          aria-label="Stream volume"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={percent}
          aria-valuetext={`${percent}%`}
          className={
            tone === "studio"
              ? "h-1 w-24 shrink-0 accent-white"
              : "h-1 w-16 shrink-0 accent-white"
          }
          onChange={(event) => {
            setTradeRoomBroadcastStreamListenVolume(Number(event.target.value) / 100)
          }}
        />
      ) : null}
      {broadcast.isInConversation ? (
        <button
          type="button"
          disabled={!broadcast.viewerMicPublishReady}
          aria-label={broadcast.viewerMicMuted ? "Unmute your mic" : "Mute your mic"}
          className={buttonClass}
          onClick={() => void toggleTradeRoomBroadcastViewerMicMuted()}
        >
          {broadcast.viewerMicMuted ? (
            <MicOff size={iconSize} aria-hidden />
          ) : (
            <Mic size={iconSize} aria-hidden />
          )}
          {tone === "studio" ? (broadcast.viewerMicMuted ? "Mic off" : "Mic on") : null}
        </button>
      ) : null}
    </>
  )
}
