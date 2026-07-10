"use client"

import { useEffect, useRef, useState } from "react"
import ReplyActionButton from "@/app/components/replies/ReplyActionButton"
import {
  ROOM_MESSAGE_REACTIONS,
  aggregateRoomMessageReactions,
  type RoomMessageReactionEmoji,
  type RoomMessageReactionRow,
} from "@/lib/roomMessageReactions"

type RoomMessageFooterProps = {
  messageId: string
  reactions: RoomMessageReactionRow[] | null | undefined
  viewerUserId: string | null | undefined
  disabled?: boolean
  onReply: () => void
  onToggle: (messageId: string, reaction: RoomMessageReactionEmoji) => void
}

export default function RoomMessageFooter({
  messageId,
  reactions,
  viewerUserId,
  disabled = false,
  onReply,
  onToggle,
}: RoomMessageFooterProps) {
  const [pickerOpen, setPickerOpen] = useState(false)
  const pickerRef = useRef<HTMLDivElement | null>(null)
  const summaries = aggregateRoomMessageReactions(reactions, viewerUserId)

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

  const handleToggle = (emoji: RoomMessageReactionEmoji) => {
    if (disabled || !viewerUserId) return
    onToggle(messageId, emoji)
    setPickerOpen(false)
  }

  return (
    <div className="mt-1">
      {summaries.length > 0 ? (
        <div className="mb-1 flex flex-wrap items-center gap-1.5">
          {summaries.map(({ emoji, count, reactedByViewer }) => (
            <button
              key={emoji}
              type="button"
              disabled={disabled || !viewerUserId}
              onClick={() => handleToggle(emoji)}
              className={
                "inline-flex items-center gap-0.5 rounded-full px-1.5 py-0.5 text-xs leading-none transition " +
                (reactedByViewer
                  ? "bg-blue-500/20 text-blue-100 ring-1 ring-blue-400/30"
                  : "bg-white/10 text-gray-300 hover:bg-white/15")
              }
              aria-label={`${emoji} ${count}${reactedByViewer ? ", you reacted" : ""}`}
            >
              <span aria-hidden>{emoji}</span>
              <span>{count}</span>
            </button>
          ))}
        </div>
      ) : null}

      <div className="flex items-center gap-3">
        <ReplyActionButton
          onReply={onReply}
          className="opacity-100"
        />
        <div ref={pickerRef} className="relative">
          <button
            type="button"
            disabled={disabled || !viewerUserId}
            onClick={() => setPickerOpen((open) => !open)}
            className="rounded px-1.5 py-0.5 text-xs text-gray-400 transition hover:bg-white/10 hover:text-gray-200 disabled:cursor-not-allowed disabled:opacity-50"
            aria-label="React"
            aria-expanded={pickerOpen}
          >
            <span aria-hidden>😊</span>
            <span className="sr-only">React</span>
          </button>

          {pickerOpen ? (
            <div className="absolute bottom-full left-0 z-20 mb-1 flex gap-0.5 rounded-lg border border-white/10 bg-[#1a1f2e] p-1 shadow-lg">
              {ROOM_MESSAGE_REACTIONS.map((emoji) => (
                <button
                  key={emoji}
                  type="button"
                  disabled={disabled || !viewerUserId}
                  onClick={() => handleToggle(emoji)}
                  className="rounded-md px-2 py-1 text-base hover:bg-white/10 disabled:opacity-50"
                  aria-label={`React with ${emoji}`}
                >
                  {emoji}
                </button>
              ))}
            </div>
          ) : null}
        </div>
      </div>
    </div>
  )
}
