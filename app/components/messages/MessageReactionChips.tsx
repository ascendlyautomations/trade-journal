"use client"

import { useState } from "react"
import {
  aggregateRoomMessageReactions,
  type MessageReactionRow,
} from "@/lib/roomMessageReactions"
import MessageReactionQuickRow from "@/app/components/messages/MessageReactionQuickRow.tsx"
import UnicodeEmojiPickerOverlay from "@/app/components/messages/UnicodeEmojiPickerOverlay.tsx"

export type MessageReactionChipsProps = {
  reactions: MessageReactionRow[] | null | undefined
  viewerUserId: string | null | undefined
  /** When false, chips render as static labels (spectators). */
  interactive?: boolean
  isOutgoing?: boolean
  onToggle?: (emoji: string) => void
  /** Compact 😊 trigger; omit when reactions are menu-only. */
  showPickerTrigger?: boolean
  className?: string
  theme?: "light" | "dark"
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
  theme = "dark",
}: MessageReactionChipsProps) {
  const [pickerOpen, setPickerOpen] = useState(false)
  const summaries = aggregateRoomMessageReactions(reactions, viewerUserId)
  const canPick =
    interactive && Boolean(viewerUserId) && typeof onToggle === "function"

  const handleToggle = (emoji: string) => {
    if (!canPick) return
    onToggle?.(emoji)
    setPickerOpen(false)
  }

  if (summaries.length === 0 && !canPick) return null
  if (summaries.length === 0 && !showPickerTrigger) return null

  const quickButton =
    "flex h-8 w-8 items-center justify-center rounded-full text-base active:bg-white/10 hover:bg-white/10"

  return (
    <>
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
          <MessageReactionQuickRow
            onQuickPick={handleToggle}
            onOpenFullPicker={() => setPickerOpen(true)}
            buttonClassName={
              quickButton +
              (isOutgoing ? " text-white/85" : " text-gray-400")
            }
            plusClassName="text-base font-bold"
          />
        ) : null}
      </div>

      {canPick ? (
        <UnicodeEmojiPickerOverlay
          open={pickerOpen}
          onClose={() => setPickerOpen(false)}
          onPick={handleToggle}
          theme={theme}
        />
      ) : null}
    </>
  )
}