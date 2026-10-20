"use client"

import { useEffect, useRef, useState } from "react"
import {
  MESSAGE_REACTIONS,
  aggregateRoomMessageReactions,
  type MessageReactionEmoji,
  type MessageReactionRow,
} from "@/lib/roomMessageReactions"

export type MessageReactionChipsProps = {
  reactions: MessageReactionRow[] | null | undefined
  viewerUserId: string | null | undefined
  /** When false, chips render as static labels (spectators). */
  interactive?: boolean
  isOutgoing?: boolean
  onToggle?: (emoji: MessageReactionEmoji) => void
  /** Compact 😊 trigger; omit when reactions are menu-only. */
  showPickerTrigger?: boolean
  className?: string
}

function chipClass(reactedByViewer: boolean, isOutgoing: boolean, interactive: boolean) {
  const base =
    "inline-flex items-center gap-0.5 rounded-full px-1.5 py-0.5 text-xs leading-none transition "
  if (!interactive) {
    return base + "bg-white/10 text-gray-300"
  }
  if (reactedByViewer) {
    return (
      base +
      (isOutgoing
        ? "bg-white/25 text-white ring-1 ring-white/40"
        : "bg-blue-500/20 text-blue-100 ring-1 ring-blue-400/30")
    )
  }
  return (
    base +
    (isOutgoing
      ? "bg-white/15 text-white/90 hover:bg-white/20"
      : "bg-white/10 text-gray-300 hover:bg-white/15")
  )
}

export default function MessageReactionChips({
  reactions,
  viewerUserId,
  interactive = true,
  isOutgoing = false,
  onToggle,
  showPickerTrigger = true,
  className = "",
}: MessageReactionChipsProps) {
  const [pickerOpen, setPickerOpen] = useState(false)
  const pickerRef = useRef<HTMLDivElement | null>(null)
  const summaries = aggregateRoomMessageReactions(reactions, viewerUserId)
  const canPick =
    interactive && Boolean(viewerUserId) && typeof onToggle === "function"

  useEffect(() => {
    if (!pickerOpen) return

    const onPointerDown = (event: MouseEvent | TouchEvent) => {
      if (!pickerRef.current?.contains(event.target as Node)) {
        setPickerOpen(false)
      }
    }

    document.addEventListener("mousedown", onPointerDown)
    document.addEventListener("touchstart", onPointerDown)
    return () => {
      document.removeEventListener("mousedown", onPointerDown)
      document.removeEventListener("touchstart", onPointerDown)
    }
  }, [pickerOpen])

  const handleToggle = (emoji: MessageReactionEmoji) => {
    if (!canPick) return
    onToggle?.(emoji)
    setPickerOpen(false)
  }

  if (summaries.length === 0 && !canPick) return null
  if (summaries.length === 0 && !showPickerTrigger) return null

  return (
    <div className={`flex flex-wrap items-center gap-1.5 ${className}`.trim()}>
      {summaries.map(({ emoji, count, reactedByViewer }) =>
        canPick ? (
          <button
            key={emoji}
            type="button"
            onClick={() => handleToggle(emoji)}
            className={chipClass(reactedByViewer, isOutgoing, true)}
            aria-label={`${emoji} ${count}${reactedByViewer ? ", you reacted" : ""}`}
          >
            <span aria-hidden>{emoji}</span>
            <span>{count}</span>
          </button>
        ) : (
          <span
            key={emoji}
            className={chipClass(reactedByViewer, isOutgoing, false)}
            aria-label={`${emoji} ${count}`}
          >
            <span aria-hidden>{emoji}</span>
            <span>{count}</span>
          </span>
        )
      )}

      {canPick && showPickerTrigger ? (
        <div ref={pickerRef} className="relative">
          <button
            type="button"
            onClick={() => setPickerOpen((open) => !open)}
            className={
              "rounded px-1 py-0.5 text-xs text-gray-400 transition hover:bg-white/10 hover:text-gray-200 " +
              (isOutgoing ? "text-white/70 hover:text-white" : "")
            }
            aria-label="React"
            aria-expanded={pickerOpen}
          >
            <span aria-hidden>😊</span>
            <span className="sr-only">React</span>
          </button>

          {pickerOpen ? (
            <div
              className="absolute bottom-full left-0 z-30 mb-1 flex gap-0.5 rounded-lg border border-white/10 bg-card/95 p-1 shadow-lg backdrop-blur-md"
              role="menu"
            >
              {MESSAGE_REACTIONS.map((emoji) => (
                <button
                  key={emoji}
                  type="button"
                  role="menuitem"
                  onClick={() => handleToggle(emoji)}
                  className="rounded-md px-2 py-1 text-base hover:bg-white/10"
                  aria-label={`React with ${emoji}`}
                >
                  {emoji}
                </button>
              ))}
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  )
}
