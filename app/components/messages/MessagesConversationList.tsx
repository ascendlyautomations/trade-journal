"use client"

import { memo } from "react"
import { sanitizeConversationListPreview } from "@/lib/storyShareMessage"
import MessagesConversationRow, {
  type MessagesConversationRowProps,
} from "./MessagesConversationRow"

export type MessagesConversationListItem = {
  id: string
  is_group: boolean
  is_pinned: boolean
  name: string | null
  displayName: string
  username: string
  profileUserId?: string | null
  lastMessage: string
  lastMessageAt?: string | null
  avatar_url: string | null
  unreadCount: number
}

type MessagesConversationListProps = {
  conversations: MessagesConversationListItem[]
  openConvoMenuId: string | null
  onOpen: MessagesConversationRowProps["onOpen"]
  onToggleMenu: MessagesConversationRowProps["onToggleMenu"]
  onPin: MessagesConversationRowProps["onPin"]
  onMarkUnread: MessagesConversationRowProps["onMarkUnread"]
  onDelete: MessagesConversationRowProps["onDelete"]
}

function MessagesConversationList({
  conversations,
  openConvoMenuId,
  onOpen,
  onToggleMenu,
  onPin,
  onMarkUnread,
  onDelete,
}: MessagesConversationListProps) {
  return (
    <div className="space-y-3">
      {conversations.map((c) => (
        <MessagesConversationRow
          key={c.id}
          conversationId={c.id}
          isGroup={c.is_group === true}
          isPinned={c.is_pinned === true}
          groupName={c.name}
          displayName={c.displayName}
          username={c.username}
          profileUserId={c.profileUserId}
          lastMessage={sanitizeConversationListPreview(c.lastMessage)}
          lastMessageAt={c.lastMessageAt}
          avatarUrl={c.avatar_url}
          unreadCount={c.unreadCount ?? 0}
          isMenuOpen={openConvoMenuId === c.id}
          onOpen={onOpen}
          onToggleMenu={onToggleMenu}
          onPin={onPin}
          onMarkUnread={onMarkUnread}
          onDelete={onDelete}
        />
      ))}
    </div>
  )
}

export default memo(MessagesConversationList)
