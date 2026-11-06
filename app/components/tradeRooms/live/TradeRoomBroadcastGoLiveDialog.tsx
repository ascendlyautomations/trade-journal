"use client"

import { useState } from "react"
import type {
  TradeRoomBroadcastVideoSource,
  TradeRoomBroadcastVoiceMode,
} from "@/lib/livekit/tradeRoomBroadcastVoiceMode.ts"

export type GoLiveDialogResult = {
  videoSource: TradeRoomBroadcastVideoSource
  voiceMode: TradeRoomBroadcastVoiceMode
  enableBroadcasterMic: boolean
}

type Props = {
  open: boolean
  onClose: () => void
  onConfirm: (result: GoLiveDialogResult) => void
  busy: boolean
}

export default function TradeRoomBroadcastGoLiveDialog({
  open,
  onClose,
  onConfirm,
  busy,
}: Props) {
  const [videoSource, setVideoSource] =
    useState<TradeRoomBroadcastVideoSource>("screen")
  const [voiceMode, setVoiceMode] =
    useState<TradeRoomBroadcastVoiceMode>("broadcast_only")
  const [enableMic, setEnableMic] = useState(true)

  if (!open) return null

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 p-4 sm:items-center"
      role="dialog"
      aria-modal="true"
      aria-labelledby="go-live-title"
    >
      <div className="w-full max-w-md rounded-xl border border-white/10 bg-zinc-900 p-4 shadow-xl">
        <h2 id="go-live-title" className="text-lg font-semibold text-white">
          Go live
        </h2>
        <p className="mt-1 text-sm text-gray-400">
          Stream video and your microphone in a dedicated live session — separate
          from General Voice.
        </p>

        <fieldset className="mt-4 space-y-2">
          <legend className="text-xs font-semibold uppercase tracking-wide text-gray-500">
            Video source
          </legend>
          <label className="flex cursor-pointer items-center gap-2 rounded-lg border border-white/10 px-3 py-2 hover:bg-white/5">
            <input
              type="radio"
              name="videoSource"
              checked={videoSource === "screen"}
              onChange={() => setVideoSource("screen")}
            />
            <span className="text-sm text-gray-200">Screen / window / tab</span>
          </label>
          <label className="flex cursor-pointer items-center gap-2 rounded-lg border border-white/10 px-3 py-2 hover:bg-white/5">
            <input
              type="radio"
              name="videoSource"
              checked={videoSource === "camera"}
              onChange={() => setVideoSource("camera")}
            />
            <span className="text-sm text-gray-200">Camera / webcam</span>
          </label>
        </fieldset>

        <fieldset className="mt-4 space-y-2">
          <legend className="text-xs font-semibold uppercase tracking-wide text-gray-500">
            Voice
          </legend>
          <label className="flex cursor-pointer items-center gap-2 rounded-lg border border-white/10 px-3 py-2 hover:bg-white/5">
            <input
              type="radio"
              name="voiceMode"
              checked={voiceMode === "broadcast_only"}
              onChange={() => setVoiceMode("broadcast_only")}
            />
            <span className="text-sm text-gray-200">
              Broadcast only — viewers watch and chat
            </span>
          </label>
          <label className="flex cursor-pointer items-center gap-2 rounded-lg border border-white/10 px-3 py-2 hover:bg-white/5">
            <input
              type="radio"
              name="voiceMode"
              checked={voiceMode === "open_voice"}
              onChange={() => setVoiceMode("open_voice")}
            />
            <span className="text-sm text-gray-200">
              Open voice — viewers can join conversation
            </span>
          </label>
        </fieldset>

        <label className="mt-4 flex cursor-pointer items-center gap-2 text-sm text-gray-200">
          <input
            type="checkbox"
            checked={enableMic}
            onChange={(e) => setEnableMic(e.target.checked)}
          />
          Include my microphone
        </label>

        <div className="mt-6 flex justify-end gap-2">
          <button
            type="button"
            disabled={busy}
            onClick={onClose}
            className="rounded-lg px-3 py-2 text-sm text-gray-300 hover:bg-white/5 disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={busy}
            onClick={() =>
              onConfirm({
                videoSource,
                voiceMode,
                enableBroadcasterMic: enableMic,
              })
            }
            className="rounded-lg bg-red-600 px-4 py-2 text-sm font-semibold text-white hover:bg-red-500 disabled:opacity-50"
          >
            {busy ? "Starting…" : "Start stream"}
          </button>
        </div>
      </div>
    </div>
  )
}
