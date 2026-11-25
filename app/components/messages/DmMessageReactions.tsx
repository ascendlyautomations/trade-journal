"use client"

import MessageReactionChips from "@/app/components/messages/MessageReactionChips"
import {
  aggregateRoomMessageReactions,
  MESSAGE_REACTION_BUBBLE_RESERVE_CLASS,
  shouldReserveMessageReactionBubbleSpace,
  type MessageReactionEmoji,
  type MessageReactionRow,
} from "@/lib/roomMessageReactions"

export { MESSAGE_REACTION_BUBBLE_RESERVE_CLASS, shouldReserveMessageReactionBubbleSpace }

type DmMessageReactionsProps = {
  reactions: MessageReactionRow[] | null | undefined
  viewerUserId: string | null | undefined
  isOutgoing: boolean
  alignEnd: boolean
  canReact: boolean
  onToggle: (emoji: MessageReactionEmoji) => void
  /** Chips float on the bubble edge; parent should reserve bottom padding. */
  attachToBubble?: boolean
}

export default function DmMessageReactions({
  reactions,
  viewerUserId,
  isOutgoing,
  alignEnd,
  canReact,
  onToggle,
  attachToBubble = false,
}: DmMessageReactionsProps) {
  const summaries = aggregateRoomMessageReactions(reactions, viewerUserId)
  const hasSummaries = summaries.length > 0

  if (!hasSummaries && !canReact) return null
  if (attachToBubble && !hasSummaries) return null

  const chips = (
    <MessageReactionChips
      reactions={reactions}
      viewerUserId={viewerUserId}
      interactive={canReact}
      isOutgoing={isOutgoing}
      onToggle={onToggle}
      showPickerTrigger={canReact && !attachToBubble}
    />
  )

  if (attachToBubble) {
    return (
      <div
        className={`pointer-events-auto absolute bottom-0 z-10 flex max-w-full ${
          alignEnd ? "right-0 translate-y-1/2" : "left-0 translate-y-1/2"
        }`}
      >
        {chips}
      </div>
    )
  }

  return (
    <div
      className={`mt-1 flex max-w-[75%] xl:max-w-[32rem] ${
        alignEnd ? "ml-auto justify-end" : "mr-auto justify-start"
      }`}
    >
      {chips}
    </div>
  )
}