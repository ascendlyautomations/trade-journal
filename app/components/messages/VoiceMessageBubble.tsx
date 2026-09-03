"use client"

import { useEffect, useMemo, useState } from "react"
import {
  formatVoiceDuration,
  voiceWaveformHeights,
} from "@/lib/voiceMessage"
import {
  getVoicePlaybackSnapshot,
  scrubVoicePlayback,
  subscribeVoicePlayback,
  toggleVoicePlayback,
} from "@/lib/voiceMessagePlayback"

type VoiceMessageBubbleProps = {
  messageId: string
  audioUrl: string
  durationMs?: number | null
  isOutgoing?: boolean
}

export default function VoiceMessageBubble({
  messageId,
  audioUrl,
  durationMs,
  isOutgoing = false,
}: VoiceMessageBubbleProps) {
  const [, tick] = useState(0)
  const snapshot = getVoicePlaybackSnapshot()
  const isActive = snapshot.messageId === messageId
  const isPlaying = isActive && snapshot.isPlaying
  const knownDuration =
    durationMs != null && Number.isFinite(durationMs)
      ? durationMs / 1000
      : undefined
  const duration = isActive && snapshot.duration > 0
    ? snapshot.duration
    : knownDuration ?? 0
  const currentTime = isActive ? snapshot.currentTime : 0
  const progress = duration > 0 ? Math.min(Math.max(currentTime / duration, 0), 1) : 0
  const bars = useMemo(() => voiceWaveformHeights(messageId), [messageId])

  useEffect(() => subscribeVoicePlayback(() => tick((value) => value + 1)), [])

  const bubbleClass = isOutgoing
    ? "bg-blue-500 text-white"
    : "bg-gray-700 text-white"
  const barActiveClass = isOutgoing ? "bg-white" : "bg-blue-400"
  const barIdleClass = isOutgoing ? "bg-white/35" : "bg-blue-400/30"

  return (
    <div
      className={`inline-flex min-w-[180px] max-w-[240px] items-center gap-2 rounded-xl px-3 py-2 ${bubbleClass}`}
      data-voice-message-id={messageId}
    >
      <button
        type="button"
        aria-label={isPlaying ? "Pause voice message" : "Play voice message"}
        className="flex h-7 w-7 shrink-0 items-center justify-center"
        onClick={() => {
          void toggleVoicePlayback(messageId, audioUrl, knownDuration).catch(() => {})
        }}
      >
        {isPlaying ? "⏸" : "▶︎"}
      </button>
      <div
        className="flex h-7 flex-1 cursor-pointer items-center gap-0.5"
        onPointerDown={(event) => {
          const rect = event.currentTarget.getBoundingClientRect()
          const update = (clientX: number) => {
            const next = (clientX - rect.left) / Math.max(rect.width, 1)
            scrubVoicePlayback(messageId, next)
            tick((value) => value + 1)
          }
          update(event.clientX)
          const onMove = (moveEvent: PointerEvent) => update(moveEvent.clientX)
          const onUp = () => {
            window.removeEventListener("pointermove", onMove)
            window.removeEventListener("pointerup", onUp)
          }
          window.addEventListener("pointermove", onMove)
          window.addEventListener("pointerup", onUp)
        }}
      >
        {bars.map((height, index) => {
          const barProgress = (index + 1) / bars.length
          const filled = barProgress <= progress
          return (
            <span
              key={index}
              className={`w-[3px] rounded-full ${filled ? barActiveClass : barIdleClass}`}
              style={{ height: `${8 + height * 16}px` }}
            />
          )
        })}
      </div>
      <span className="min-w-[36px] text-right font-mono text-xs opacity-90">
        {formatVoiceDuration(isActive ? currentTime : duration)}
      </span>
    </div>
  )
}
