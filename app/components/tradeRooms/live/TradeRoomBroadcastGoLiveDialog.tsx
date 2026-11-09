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
          <label
            className={`flex cursor-pointer gap-2 rounded-lg border border-white/10 px-3 py-2 hover:bg-white/5 ${
              videoSource === "screen" ? "items-start" : "items-center"
            }`}
          >
            <input
              type="radio"
              name="videoSource"
              checked={videoSource === "screen"}
              onChange={() => setVideoSource("screen")}
              className={videoSource === "screen" ? "mt-1 shrink-0" : "shrink-0"}
            />
            <span className="text-sm text-gray-200">
              <span className="font-medium text-white">Screen / window / tab</span>
              {videoSource === "screen" ? (
                <span className="mt-0.5 block text-xs text-gray-500">
                  Make sure screen sharing is allowed in your browser and system
                  settings. You may need to enable Screen Recording permissions on
                  macOS.
                </span>
              ) : null}
            </span>
          </label>
          <label
            className={`flex cursor-pointer gap-2 rounded-lg border border-white/10 px-3 py-2 hover:bg-white/5 ${
              videoSource === "camera" ? "items-start" : "items-center"
            }`}
          >
            <input
              type="radio"
              name="videoSource"
              checked={videoSource === "camera"}
              onChange={() => setVideoSource("camera")}
              className={videoSource === "camera" ? "mt-1 shrink-0" : "shrink-0"}
            />
            <span className="text-sm text-gray-200">
              <span className="font-medium text-white">Camera / webcam</span>
              {videoSource === "camera" ? (
                <span className="mt-0.5 block text-xs text-gray-500">
                  Make sure your browser has permission to access your camera and
                  microphone before starting your stream.
                </span>
              ) : null}
            </span>
          </label>
          <label
            className={`flex cursor-pointer gap-2 rounded-lg border border-white/10 px-3 py-2 hover:bg-white/5 ${
              videoSource === "obs" ? "items-start" : "items-center"
            }`}
          >
            <input
              type="radio"
              name="videoSource"
              checked={videoSource === "obs"}
              onChange={() => setVideoSource("obs")}
              className={videoSource === "obs" ? "mt-1 shrink-0" : "shrink-0"}
            />
            <span className="text-sm text-gray-200">
              <span className="font-medium text-white">OBS Studio</span>
              {videoSource === "obs" ? (
                <span className="mt-0.5 block text-xs text-gray-500">
                  Program video and audio from OBS via RTMP. You stay connected for
                  moderation, chat, and Invite to Talk — no browser screen or camera
                  capture required.
                </span>
              ) : null}
            </span>
          </label>
        </fieldset>

        <fieldset className="mt-4 space-y-2">
          <legend className="text-xs font-semibold uppercase tracking-wide text-gray-500">
            Voice
          </legend>
          <label
            className={`flex cursor-pointer gap-2 rounded-lg border border-white/10 px-3 py-2 hover:bg-white/5 ${
              voiceMode === "broadcast_only" ? "items-start" : "items-center"
            }`}
          >
            <input
              type="radio"
              name="voiceMode"
              checked={voiceMode === "broadcast_only"}
              onChange={() => setVoiceMode("broadcast_only")}
              className={
                voiceMode === "broadcast_only" ? "mt-1 shrink-0" : "shrink-0"
              }
            />
            <span className="text-sm text-gray-200">
              <span className="font-medium text-white">Broadcast only</span>
              {voiceMode === "broadcast_only" ? (
                <span className="mt-0.5 block text-xs text-gray-500">
                  Viewers watch and chat
                </span>
              ) : null}
            </span>
          </label>
          <label
            className={`flex cursor-pointer gap-2 rounded-lg border border-white/10 px-3 py-2 hover:bg-white/5 ${
              voiceMode === "open_voice" ? "items-start" : "items-center"
            }`}
          >
            <input
              type="radio"
              name="voiceMode"
              checked={voiceMode === "open_voice"}
              onChange={() => setVoiceMode("open_voice")}
              className={voiceMode === "open_voice" ? "mt-1 shrink-0" : "shrink-0"}
            />
            <span className="text-sm text-gray-200">
              <span className="font-medium text-white">Open voice</span>
              {voiceMode === "open_voice" ? (
                <span className="mt-0.5 block text-xs text-gray-500">
                  Viewers can join conversation
                </span>
              ) : null}
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
            {busy
              ? "Starting…"
              : videoSource === "obs"
                ? "Set up OBS"
                : "Start stream"}
          </button>
        </div>
      </div>
    </div>
  )
}
