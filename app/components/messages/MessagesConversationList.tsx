"use client"

import { memo } from "react"
import { sanitizeConversationListPreview } from "@/lib/storyShareMessage"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
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
  selectedConversationId?: string | null
  openConvoMenuId: string | null
  onOpen: MessagesConversationRowProps["onOpen"]
  onToggleMenu: MessagesConversationRowProps["onToggleMenu"]
  onPin: MessagesConversationRowProps["onPin"]
  onMarkUnread: MessagesConversationRowProps["onMarkUnread"]
  onDelete: MessagesConversationRowProps["onDelete"]
}

function MessagesConversationList({
  conversations,
  selectedConversationId = null,
  openConvoMenuId,
  onOpen,
  onToggleMenu,
  onPin,
  onMarkUnread,
  onDelete,
}: MessagesConversationListProps) {
  const isNativeIos = useIsNativeIos()
  const firstUnpinnedIndex = conversations.findIndex((c) => c.is_pinned !== true)
  const showPinnedLabel = !isNativeIos && conversations[0]?.is_pinned === true

  return (
    <div className={isNativeIos ? "space-y-3" : "space-y-3 max-md:space-y-0"}>
      {conversations.map((c, index) => (
        <div key={c.id}>
          {showPinnedLabel && index === 0 ? (
            <p className="px-4 pb-1 pt-2 text-[13px] font-semibold text-[color:var(--tt-text-muted,#57606a)] md:hidden">
              Pinned
            </p>
          ) : null}
          {showPinnedLabel &&
          firstUnpinnedIndex > 0 &&
          index === firstUnpinnedIndex ? (
            <p className="px-4 pb-1 pt-3 text-[13px] font-semibold text-[color:var(--tt-text-muted,#57606a)] md:hidden">
              Direct Messages
            </p>
          ) : null}
          <MessagesConversationRow
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
            selected={selectedConversationId === c.id}
            isMenuOpen={openConvoMenuId === c.id}
            onOpen={onOpen}
            onToggleMenu={onToggleMenu}
            onPin={onPin}
            onMarkUnread={onMarkUnread}
            onDelete={onDelete}
          />
        </div>
      ))}
    </div>
  )
}

export default memo(MessagesConversationList)
