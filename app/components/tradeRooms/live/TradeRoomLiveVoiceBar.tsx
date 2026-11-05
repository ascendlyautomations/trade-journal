"use client"

import { ConnectionState } from "livekit-client"
import { Mic, MicOff, PhoneOff, Users } from "lucide-react"
import { useState } from "react"
import { useTradeRoomLiveVoice } from "./useTradeRoomLiveVoice.ts"

export default function TradeRoomLiveVoiceBar() {
  const voice = useTradeRoomLiveVoice()
  const [expanded, setExpanded] = useState(false)

  if (!voice.session) return null

  const connecting = voice.connectionState === ConnectionState.Connecting
  const muted = voice.session.canPublish && !voice.isMicrophoneEnabled

  return (
    <div
      className="pointer-events-auto fixed inset-x-0 bottom-0 z-[60] border-t border-emerald-500/30 bg-[#0b1220]/95 px-3 py-2 text-white shadow-lg backdrop-blur-md md:bottom-0"
      style={{ paddingBottom: "max(0.5rem, env(safe-area-inset-bottom))" }}
    >
      <div className="mx-auto flex max-w-3xl items-center gap-2">
        <button
          type="button"
          className="flex min-w-0 flex-1 flex-col text-left"
          onClick={() => setExpanded((v) => !v)}
        >
          <span className="truncate text-xs font-medium text-emerald-300">
            Live voice · {voice.session.roomLabel}
          </span>
          <span className="truncate text-[11px] text-gray-400">
            {voice.session.channelLabel}
            {connecting ? " · Connecting…" : voice.session.canPublish ? "" : " · Listen only"}
          </span>
        </button>
        {voice.session.canPublish ? (
          <button
            type="button"
            aria-label={muted ? "Unmute microphone" : "Mute microphone"}
            disabled={voice.isBusy || connecting}
            onClick={() => void voice.setMuted(!muted)}
            className="rounded-full bg-white/10 p-2 hover:bg-white/15 disabled:opacity-50"
          >
            {muted ? <MicOff className="h-5 w-5" /> : <Mic className="h-5 w-5" />}
          </button>
        ) : null}
        <button
          type="button"
          aria-label="Show participants"
          onClick={() => setExpanded((v) => !v)}
          className="rounded-full bg-white/10 p-2 hover:bg-white/15"
        >
          <Users className="h-5 w-5" />
        </button>
        <button
          type="button"
          aria-label="Leave live voice"
          disabled={voice.isBusy}
          onClick={() => void voice.leave()}
          className="rounded-full bg-red-500/25 p-2 text-red-100 hover:bg-red-500/40 disabled:opacity-50"
        >
          <PhoneOff className="h-5 w-5" />
        </button>
      </div>
      {expanded ? (
        <ul className="mx-auto mt-2 max-h-32 max-w-3xl overflow-y-auto text-xs text-gray-300">
          {voice.participants.length === 0 ? (
            <li className="px-1 py-1 text-gray-500">No participants yet</li>
          ) : (
            voice.participants.map((p) => (
              <li key={p.identity} className="flex items-center gap-2 px-1 py-0.5">
                <span
                  className={`h-2 w-2 rounded-full ${p.isSpeaking ? "bg-emerald-400" : "bg-gray-600"}`}
                />
                <span className="truncate">
                  {p.name}
                  {p.isLocal ? " (you)" : ""}
                </span>
                {p.isMuted ? (
                  <MicOff className="h-3 w-3 shrink-0 text-gray-500" aria-hidden />
                ) : null}
              </li>
            ))
          )}
        </ul>
      ) : null}
      {voice.error ? (
        <p className="mx-auto mt-1 max-w-3xl text-xs text-red-300">{voice.error}</p>
      ) : null}
    </div>
  )
}
