"use client"

import MessageReactionChips from "@/app/components/messages/MessageReactionChips"
import {
  aggregateRoomMessageReactions,
  type MessageReactionEmoji,
  type MessageReactionRow,
} from "@/lib/roomMessageReactions"

type DmMessageReactionsProps = {
  reactions: MessageReactionRow[] | null | undefined
  viewerUserId: string | null | undefined
  isOutgoing: boolean
  alignEnd: boolean
  canReact: boolean
  onToggle: (emoji: MessageReactionEmoji) => void
}

export default function DmMessageReactions({
  reactions,
  viewerUserId,
  isOutgoing,
  alignEnd,
  canReact,
  onToggle,
}: DmMessageReactionsProps) {
  const hasSummaries =
    aggregateRoomMessageReactions(reactions, viewerUserId).length > 0

  if (!hasSummaries && !canReact) return null

  return (
    <div
      className={`mt-1 flex max-w-[75%] xl:max-w-[32rem] ${
        alignEnd ? "ml-auto justify-end" : "mr-auto justify-start"
      }`}
    >
      <MessageReactionChips
        reactions={reactions}
        viewerUserId={viewerUserId}
        interactive={canReact}
        isOutgoing={isOutgoing}
        onToggle={onToggle}
        showPickerTrigger={canReact}
      />
    </div>
  )
}
