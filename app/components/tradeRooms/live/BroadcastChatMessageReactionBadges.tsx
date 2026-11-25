"use client"

import {
  aggregateRoomMessageReactions,
  type MessageReactionRow,
} from "@/lib/roomMessageReactions"
import type { BroadcastChatReactionRow } from "@/lib/livekit/client/tradeRoomBroadcastChatReaction.ts"

type Props = {
  reactions: BroadcastChatReactionRow[]
  viewerUserId: string | null
  onToggle?: (emoji: string) => void
}

export default function BroadcastChatMessageReactionBadges({
  reactions,
  viewerUserId,
  onToggle,
}: Props) {
  const asRows: MessageReactionRow[] = reactions.map((row) => ({
    id: `${row.messageId}-${row.userId}`,
    message_id: row.messageId,
    user_id: row.userId,
    reaction: row.emoji,
  }))
  const summaries = aggregateRoomMessageReactions(asRows, viewerUserId)
  if (summaries.length === 0) return null

  return (
    <div className="flex flex-wrap items-center gap-0.5 pt-0.5">
      {summaries.map(({ emoji, count, reactedByViewer }) =>
        onToggle ? (
          <button
            key={emoji}
            type="button"
            onClick={() => onToggle(emoji)}
            className={`inline-flex items-center gap-px rounded-full px-1 py-px text-[10px] leading-none ${
              reactedByViewer
                ? "bg-violet-500/25 text-violet-100 ring-1 ring-violet-400/35"
                : "bg-white/10 text-gray-400 hover:bg-white/15"
            }`}
            aria-label={`${emoji} ${count}${reactedByViewer ? ", you reacted" : ""}`}
          >
            <span aria-hidden>{emoji}</span>
            {count > 1 ? <span>{count}</span> : null}
          </button>
        ) : (
          <span
            key={emoji}
            className="inline-flex items-center gap-px rounded-full bg-white/10 px-1 py-px text-[10px] leading-none text-gray-400"
          >
            <span aria-hidden>{emoji}</span>
            {count > 1 ? <span>{count}</span> : null}
          </span>
        )
      )}
    </div>
  )
}