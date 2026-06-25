"use client"

import { memo, useEffect, useState } from "react"
import {
  ProfileAvatarLink,
  ProfileUsernameLink,
} from "@/app/components/ProfileLink"
import { formatConversationListTime } from "@/lib/formatRelativeTime"

export type MessagesConversationRowProps = {
  conversationId: string
  isGroup: boolean
  isPinned: boolean
  groupName: string | null
  displayName: string
  username: string
  profileUserId?: string | null
  lastMessage: string
  lastMessageAt?: string | null
  avatarUrl: string | null
  unreadCount: number
  isMenuOpen: boolean
  onOpen: (conversationId: string) => void
  onToggleMenu: (conversationId: string) => void
  onPin: (conversationId: string, isPinned: boolean) => void
  onMarkUnread: (conversationId: string) => void
  onDelete: (conversationId: string) => void
}

function MessagesConversationRow({
  conversationId,
  isGroup,
  isPinned,
  groupName,
  displayName,
  username,
  profileUserId,
  lastMessage,
  lastMessageAt,
  avatarUrl,
  unreadCount,
  isMenuOpen,
  onOpen,
  onToggleMenu,
  onPin,
  onMarkUnread,
  onDelete,
}: MessagesConversationRowProps) {
  const [now, setNow] = useState(() => Date.now())

  useEffect(() => {
    if (!lastMessageAt) return
    const id = window.setInterval(() => setNow(Date.now()), 30_000)
    return () => window.clearInterval(id)
  }, [lastMessageAt])

  const timeLabel = lastMessageAt
    ? formatConversationListTime(lastMessageAt, now)
    : ""

  return (
    <div
      onClick={() => onOpen(conversationId)}
      className="relative bg-white/5 border border-white/10 p-4 rounded-xl cursor-pointer hover:bg-white/10 transition"
    >
      <button
        type="button"
        aria-label="Conversation options"
        onClick={(e) => {
          e.stopPropagation()
          onToggleMenu(conversationId)
        }}
        className="absolute right-3 top-3 z-10 px-2 py-1 rounded bg-black/40 hover:bg-black/60 text-sm text-white cursor-pointer"
      >
        ⋯
      </button>
      {isMenuOpen ? (
        <div
          className="absolute right-3 top-10 z-20 w-40 rounded-lg border border-white/10 bg-[#0f172a] py-1 shadow-lg"
          onClick={(e) => e.stopPropagation()}
        >
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation()
              onPin(conversationId, isPinned)
            }}
            className="w-full px-3 py-2 text-left text-sm text-white hover:bg-[#1f2937] cursor-pointer"
          >
            {isPinned ? "Unpin Chat" : "Pin Chat"}
          </button>
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation()
              onMarkUnread(conversationId)
            }}
            className="w-full px-3 py-2 text-left text-sm text-white hover:bg-[#1f2937] cursor-pointer"
          >
            Mark as Unread
          </button>
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation()
              onDelete(conversationId)
            }}
            className="w-full px-3 py-2 text-left text-sm text-white hover:bg-white/10 cursor-pointer"
          >
            Delete Chat
          </button>
        </div>
      ) : null}
      <div className="flex items-center gap-3 pr-10">
        {!isGroup && profileUserId ? (
          <ProfileAvatarLink
            userId={profileUserId}
            username={username}
            src={avatarUrl}
            stopPropagation
            imgClassName="h-10 w-10 shrink-0 rounded-full object-cover transition hover:scale-105"
          />
        ) : avatarUrl ? (
          <img
            src={avatarUrl}
            alt=""
            loading="lazy"
            decoding="async"
            className="h-10 w-10 shrink-0 rounded-full object-cover transition hover:scale-105"
          />
        ) : (
          <div className="h-10 w-10 shrink-0 rounded-full bg-gray-600" />
        )}

        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2 min-w-0">
            <p className="min-w-0 flex-1 truncate font-semibold text-emerald-400">
              {isGroup ? (
                <>
                  {groupName || displayName}
                  {isPinned ? (
                    <span className="ml-2 text-xs text-yellow-400">📌</span>
                  ) : null}
                </>
              ) : profileUserId ? (
                <>
                  <ProfileUsernameLink
                    userId={profileUserId}
                    username={username}
                    stopPropagation
                    className="hover:underline"
                  >
                    @{username}
                  </ProfileUsernameLink>
                  {isPinned ? (
                    <span className="ml-2 text-xs text-yellow-400">📌</span>
                  ) : null}
                </>
              ) : (
                <>
                  @{username}
                  {isPinned ? (
                    <span className="ml-2 text-xs text-yellow-400">📌</span>
                  ) : null}
                </>
              )}
            </p>
            {timeLabel ? (
              <time
                dateTime={lastMessageAt ?? undefined}
                className="shrink-0 text-xs tabular-nums whitespace-nowrap text-gray-400"
              >
                {timeLabel}
              </time>
            ) : null}
          </div>

          <p className="text-sm text-gray-400 truncate">{lastMessage}</p>
        </div>

        {unreadCount > 0 ? (
          <span className="shrink-0 bg-red-500 text-white text-xs px-2 py-1 rounded-full tabular-nums">
            {unreadCount > 9 ? "9+" : unreadCount}
          </span>
        ) : null}
      </div>
    </div>
  )
}

export default memo(MessagesConversationRow)
