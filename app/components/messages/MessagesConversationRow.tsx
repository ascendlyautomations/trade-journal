"use client"

import { memo, useEffect, useState } from "react"
import {
  ProfileAvatarLink,
  ProfileUsernameLink,
} from "@/app/components/ProfileLink"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import { formatConversationListTime } from "@/lib/formatRelativeTime"
import { useIsNativeIos } from "@/lib/useIsNativeIos"

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
  selected?: boolean
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
  selected = false,
  isMenuOpen,
  onOpen,
  onToggleMenu,
  onPin,
  onMarkUnread,
  onDelete,
}: MessagesConversationRowProps) {
  const isNativeIos = useIsNativeIos()
  const phoneWeb = !isNativeIos
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
      className={`relative cursor-pointer rounded-xl border p-4 transition ${
        selected
          ? "border-blue-400/40 bg-blue-500/20"
          : "border-white/10 bg-white/5 hover:bg-white/10"
      }${
          phoneWeb
          ? " tt-mobile-web-press max-md:rounded-none max-md:border-0 max-md:border-b max-md:border-white/10 max-md:bg-transparent max-md:px-3 max-md:py-2 max-md:hover:bg-white/5"
          : ""
      }`}
    >
      <button
        type="button"
        aria-label="Conversation options"
        onClick={(e) => {
          e.stopPropagation()
          onToggleMenu(conversationId)
        }}
        className={`absolute right-3 top-3 z-10 cursor-pointer rounded-lg border border-white/10 bg-white/10 px-2 py-1 text-sm text-white hover:bg-white/20${
          phoneWeb
            ? " max-md:right-1.5 max-md:top-1/2 max-md:min-h-11 max-md:min-w-11 max-md:-translate-y-1/2 max-md:border-0 max-md:bg-transparent max-md:px-2 max-md:py-2 max-md:text-[color:var(--tt-text-muted,#57606a)]"
            : ""
        }`}
      >
        ⋯
      </button>
      {isMenuOpen ? (
        <div
          className="absolute right-3 top-10 z-20 w-40 rounded-lg border border-white/10 bg-card/95 py-1 shadow-lg backdrop-blur-md"
          onClick={(e) => e.stopPropagation()}
        >
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation()
              onPin(conversationId, isPinned)
            }}
            className="w-full px-3 py-2 text-left text-sm text-white hover:bg-white/10 cursor-pointer"
          >
            {isPinned ? "Unpin Chat" : "Pin Chat"}
          </button>
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation()
              onMarkUnread(conversationId)
            }}
            className="w-full px-3 py-2 text-left text-sm text-white hover:bg-white/10 cursor-pointer"
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
      <div className={`flex items-center gap-3 pr-10${phoneWeb ? " max-md:min-h-11 max-md:pr-9" : ""}`}>
        {!isGroup && profileUserId ? (
          <ProfileAvatarLink
            userId={profileUserId}
            username={username}
            src={avatarUrl}
            stopPropagation
            imgClassName={`h-10 w-10 shrink-0 rounded-full object-cover transition hover:scale-105${
              phoneWeb ? " max-md:h-[52px] max-md:w-[52px]" : ""
            }`}
          />
        ) : (
          <ProfileAvatarImg
            src={avatarUrl}
            className={`h-10 w-10 shrink-0 transition hover:scale-105${
              phoneWeb ? " max-md:h-[52px] max-md:w-[52px]" : ""
            }`}
          />
        )}

        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2 min-w-0">
            <div className="flex min-w-0 flex-1 items-center gap-2 overflow-hidden">
              <p className="min-w-0 truncate font-semibold text-white max-md:text-[color:var(--tt-text,#f0f3f6)]">
                {phoneWeb ? (
                  <span className="md:hidden">
                    {isGroup ? groupName || displayName : displayName || `@${username}`}
                    {isPinned ? (
                      <span className="ml-2 text-xs text-yellow-400">📌</span>
                    ) : null}
                  </span>
                ) : null}
                <span className={phoneWeb ? "hidden md:inline" : undefined}>
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
                </span>
              </p>
              {unreadCount > 0 ? (
                <span
                  className={`shrink-0 bg-red-500 text-white text-xs px-2 py-1 rounded-full tabular-nums${
                    phoneWeb
                      ? " max-md:bg-[#4EC4E0] max-md:px-1.5 max-md:py-0.5 max-md:text-[11px] max-md:font-semibold"
                      : ""
                  }`}
                >
                  {unreadCount > 9 ? "9+" : unreadCount}
                </span>
              ) : null}
            </div>
            {timeLabel ? (
              <time
                dateTime={lastMessageAt ?? undefined}
                className={`shrink-0 text-xs tabular-nums whitespace-nowrap text-gray-400${
                  phoneWeb
                    ? unreadCount > 0
                      ? " max-md:text-[#4EC4E0]"
                      : " max-md:text-[color:var(--tt-text-muted,#57606a)]"
                    : ""
                }`}
              >
                {timeLabel}
              </time>
            ) : null}
          </div>

          {!isGroup && phoneWeb && username ? (
            <p className="truncate text-[13px] text-[color:var(--tt-text-muted,#57606a)] md:hidden">
              @{username}
            </p>
          ) : null}
          <p
            className={`text-sm text-gray-400 truncate${
              phoneWeb
                ? unreadCount > 0
                  ? " max-md:line-clamp-2 max-md:whitespace-normal max-md:text-[15px] max-md:leading-snug max-md:text-[color:var(--tt-text,#f0f3f6)]"
                  : " max-md:line-clamp-2 max-md:whitespace-normal max-md:text-[15px] max-md:leading-snug max-md:text-[color:var(--tt-text-muted,#57606a)]"
                : ""
            }`}
          >
            {lastMessage}
          </p>
        </div>
      </div>
    </div>
  )
}

export default memo(MessagesConversationRow)
