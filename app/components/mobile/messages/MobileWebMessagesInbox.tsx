"use client"

import Link from "next/link"
import { useMemo, useState } from "react"
import MessagesConversationRow, {
  type MessagesConversationRowProps,
} from "@/app/components/messages/MessagesConversationRow"
import type { MessagesConversationListItem } from "@/app/components/messages/MessagesConversationList"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import { sanitizeConversationListPreview } from "@/lib/storyShareMessage"
import { isDemoUserId } from "@/lib/demo/constants"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { fetchDemoMemberRooms } from "@/lib/demo/demoRooms"
import {
  mobileWebInboxHasVisibleRows,
  mobileWebInboxTradeRoomHref,
  MOBILE_WEB_MESSAGES_INBOX_PREVIEW_LIMIT,
  normalizeMobileWebInboxTradeRoom,
  sliceMobileWebInboxPreview,
  splitMobileWebMessagesInbox,
  type MobileWebInboxTradeRoom,
} from "@/lib/mobileWebMessagesInbox"
import { readRoomSession } from "@/lib/roomSessionCache"
import { useUserProfile } from "@/lib/UserProfileProvider"

function listInboxTradeRooms(userId: string | null | undefined): MobileWebInboxTradeRoom[] {
  if (!userId) return []
  const raw =
    isDemoUserId(userId) || isDemoModeActive()
      ? fetchDemoMemberRooms(userId)
      : (readRoomSession(userId)?.rooms ?? [])
  return raw
    .map(normalizeMobileWebInboxTradeRoom)
    .filter((room): room is MobileWebInboxTradeRoom => room != null)
}

const SECTION_LABEL =
  "px-4 pb-1 pt-3 text-[13px] font-semibold text-[color:var(--tt-text-muted,#57606a)]"
const MUTED = "text-[color:var(--tt-text-muted,#57606a)]"
const TEXT = "text-[color:var(--tt-text,#f0f3f6)]"

type MobileWebMessagesInboxProps = {
  conversations: MessagesConversationListItem[]
  search: string
  selectedConversationId?: string | null
  openConvoMenuId: string | null
  onOpen: MessagesConversationRowProps["onOpen"]
  onToggleMenu: MessagesConversationRowProps["onToggleMenu"]
  onPin: MessagesConversationRowProps["onPin"]
  onMarkUnread: MessagesConversationRowProps["onMarkUnread"]
  onDelete: MessagesConversationRowProps["onDelete"]
}

function SectionToggle({
  expanded,
  onToggle,
}: {
  expanded: boolean
  onToggle: () => void
}) {
  return (
    <button
      type="button"
      onClick={onToggle}
      className="flex min-h-11 w-full items-center justify-center px-3 py-2 text-[15px] font-semibold text-[#4EC4E0]"
      aria-expanded={expanded}
    >
      {expanded ? "Show Less" : "Show More"}
    </button>
  )
}

function TradeRoomRow({ room }: { room: MobileWebInboxTradeRoom }) {
  const href = mobileWebInboxTradeRoomHref(room)
  return (
    <Link
      href={href}
      prefetch={false}
      className="flex min-h-11 items-center gap-3 border-b border-white/10 px-3 py-2"
    >
      <ProfileAvatarImg
        src={room.image_url}
        className="h-[52px] w-[52px] shrink-0"
      />
      <div className="min-w-0 flex-1">
        <p className={`truncate text-[16px] font-semibold ${TEXT}`}>{room.name}</p>
        <p className={`truncate text-[13px] ${MUTED}`}>
          {room.is_private ? "Private" : "Public"}
          {room.description ? ` · ${room.description}` : ""}
        </p>
      </div>
    </Link>
  )
}

function ConversationRows({
  conversations,
  selectedConversationId,
  openConvoMenuId,
  onOpen,
  onToggleMenu,
  onPin,
  onMarkUnread,
  onDelete,
}: {
  conversations: MessagesConversationListItem[]
} & Omit<MobileWebMessagesInboxProps, "conversations" | "search">) {
  return (
    <>
      {conversations.map((conversation) => (
        <MessagesConversationRow
          key={conversation.id}
          conversationId={conversation.id}
          isGroup={conversation.is_group === true}
          isPinned={conversation.is_pinned === true}
          groupName={conversation.name}
          displayName={conversation.displayName}
          username={conversation.username}
          profileUserId={conversation.profileUserId}
          lastMessage={sanitizeConversationListPreview(conversation.lastMessage)}
          lastMessageAt={conversation.lastMessageAt}
          avatarUrl={conversation.avatar_url}
          unreadCount={conversation.unreadCount ?? 0}
          selected={selectedConversationId === conversation.id}
          isMenuOpen={openConvoMenuId === conversation.id}
          onOpen={onOpen}
          onToggleMenu={onToggleMenu}
          onPin={onPin}
          onMarkUnread={onMarkUnread}
          onDelete={onDelete}
        />
      ))}
    </>
  )
}

export default function MobileWebMessagesInbox({
  conversations,
  search,
  selectedConversationId = null,
  openConvoMenuId,
  onOpen,
  onToggleMenu,
  onPin,
  onMarkUnread,
  onDelete,
}: MobileWebMessagesInboxProps) {
  const { user } = useUserProfile()
  const [directMessagesExpanded, setDirectMessagesExpanded] = useState(false)
  const [tradeRoomsExpanded, setTradeRoomsExpanded] = useState(false)

  const rooms = useMemo(
    () => listInboxTradeRooms(user?.id),
    [user?.id]
  )

  const sections = useMemo(
    () =>
      splitMobileWebMessagesInbox({
        conversations,
        rooms,
        viewerId: user?.id,
        search,
      }),
    [conversations, rooms, search, user?.id]
  )

  const searchActive = search.trim().length > 0
  const showDirectMessagesToggle =
    sections.directMessages.length > MOBILE_WEB_MESSAGES_INBOX_PREVIEW_LIMIT
  const showTradeRoomsToggle =
    sections.joinedRooms.length > MOBILE_WEB_MESSAGES_INBOX_PREVIEW_LIMIT
  const visibleDirectMessages = sliceMobileWebInboxPreview(
    sections.directMessages,
    searchActive || directMessagesExpanded
  )
  const visibleJoinedRooms = sliceMobileWebInboxPreview(
    sections.joinedRooms,
    searchActive || tradeRoomsExpanded
  )
  const hasRows = mobileWebInboxHasVisibleRows(sections)

  if (!hasRows) {
    return (
      <div className="px-4 py-10 text-center">
        <p className={`text-[17px] font-semibold ${TEXT}`}>
          {searchActive ? "No matches" : "No Conversations Yet"}
        </p>
        <p className={`mt-1 text-[15px] ${MUTED}`}>
          {searchActive
            ? "Try a different name or room."
            : "Start chatting with traders in the community."}
        </p>
        {!searchActive ? (
          <Link
            href="/explore"
            prefetch={false}
            className="mt-3 inline-block text-[15px] font-medium text-[#4EC4E0]"
          >
            Explore Traders
          </Link>
        ) : null}
      </div>
    )
  }

  const rowProps = {
    selectedConversationId,
    openConvoMenuId,
    onOpen,
    onToggleMenu,
    onPin,
    onMarkUnread,
    onDelete,
  }

  return (
    <div className="space-y-0">
      {sections.pinned.length > 0 ? (
        <section>
          <p className={SECTION_LABEL}>Pinned</p>
          <ConversationRows conversations={sections.pinned} {...rowProps} />
        </section>
      ) : null}

      {sections.ownedRoom ? (
        <section>
          <p className={SECTION_LABEL}>Your Trade Room</p>
          <TradeRoomRow room={sections.ownedRoom} />
        </section>
      ) : null}

      {sections.directMessages.length > 0 ? (
        <section>
          <p className={SECTION_LABEL}>Direct Messages</p>
          <ConversationRows conversations={visibleDirectMessages} {...rowProps} />
          {showDirectMessagesToggle && !searchActive ? (
            <SectionToggle
              expanded={directMessagesExpanded}
              onToggle={() => setDirectMessagesExpanded((open) => !open)}
            />
          ) : null}
        </section>
      ) : null}

      {sections.joinedRooms.length > 0 ? (
        <section>
          <p className={`${SECTION_LABEL} flex items-center gap-1.5`}>
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.75"
              strokeLinecap="round"
              strokeLinejoin="round"
              className="h-4 w-4 shrink-0 text-[#4EC4E0]"
              aria-hidden
            >
              <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
              <circle cx="9" cy="7" r="4" />
              <path d="M22 21v-2a4 4 0 0 0-3-3.87" />
              <path d="M16 3.13a4 4 0 0 1 0 7.75" />
            </svg>
            Trade Rooms
          </p>
          {visibleJoinedRooms.map((room) => (
            <TradeRoomRow key={room.id} room={room} />
          ))}
          {showTradeRoomsToggle && !searchActive ? (
            <SectionToggle
              expanded={tradeRoomsExpanded}
              onToggle={() => setTradeRoomsExpanded((open) => !open)}
            />
          ) : null}
        </section>
      ) : null}
    </div>
  )
}
