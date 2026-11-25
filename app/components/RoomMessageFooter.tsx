"use client"

import ReplyActionButton from "@/app/components/replies/ReplyActionButton"
import MessageReactionChips from "@/app/components/messages/MessageReactionChips"
import {
  aggregateRoomMessageReactions,
  type MessageReactionEmoji,
  type MessageReactionRow,
} from "@/lib/roomMessageReactions"

type RoomMessageFooterProps = {
  messageId: string
  reactions: MessageReactionRow[] | null | undefined
  viewerUserId: string | null | undefined
  /** When true, show chips only (spectators / needs join). */
  readOnly?: boolean
  disabled?: boolean
  onReply?: () => void
  onToggle: (messageId: string, reaction: MessageReactionEmoji) => void
  attachToBubble?: boolean
}

export default function RoomMessageFooter({
  messageId,
  reactions,
  viewerUserId,
  readOnly = false,
  disabled = false,
  onReply,
  onToggle,
  attachToBubble = false,
}: RoomMessageFooterProps) {
  const interactive = !readOnly && !disabled && Boolean(viewerUserId)
  const hasSummaries =
    aggregateRoomMessageReactions(reactions, viewerUserId).length > 0

  if (!hasSummaries && !interactive) return null
  if (attachToBubble && !hasSummaries) return null

  const handleToggle = (emoji: MessageReactionEmoji) => {
    if (!interactive) return
    onToggle(messageId, emoji)
  }

  const chips = (
    <MessageReactionChips
      reactions={reactions}
      viewerUserId={viewerUserId}
      interactive={interactive}
      onToggle={handleToggle}
      showPickerTrigger={interactive && !attachToBubble}
    />
  )

  if (attachToBubble) {
    return (
      <div className="pointer-events-auto absolute bottom-2 left-3 right-3 z-10 flex flex-wrap items-center gap-3">
        {chips}
        {onReply && !readOnly ? (
          <ReplyActionButton onReply={onReply} className="opacity-100" />
        ) : null}
      </div>
    )
  }

  if (readOnly) {
    if (!hasSummaries) return null
    return <div className="mt-1">{chips}</div>
  }

  return (
    <div className="mt-1 flex flex-wrap items-center gap-3">
      {chips}
      {onReply ? (
        <ReplyActionButton onReply={onReply} className="opacity-100" />
      ) : null}
    </div>
  )
}