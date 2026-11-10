"use client"

import { ChevronLeft } from "lucide-react"
import StorageImage from "@/app/components/ui/StorageImage"
import ShareRoomMenu from "@/app/components/ShareRoomMenu"
import type { TradeRoomRow } from "@/lib/tradeRoomClient"

const ICON =
  "inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-[color:var(--tt-text,#f0f3f6)] transition active:bg-white/10"

type MobileWebRoomConversationHeaderProps = {
  roomName: string
  roomImageSrc: string
  memberSummary: string | null
  onBack: () => void
  roomBellEnabled: boolean
  onOpenNotifications: () => void
  isOwner: boolean
  canShowActions: boolean
  onOpenSettings?: () => void
  onLeave?: () => void
  selectedRoom: TradeRoomRow | null
  inviteLink: string | null
  user: { id: string; username?: string | null } | null
  onCopyLink: () => void
}

export default function MobileWebRoomConversationHeader({
  roomName,
  roomImageSrc,
  memberSummary,
  onBack,
  roomBellEnabled,
  onOpenNotifications,
  isOwner,
  canShowActions,
  onOpenSettings,
  onLeave,
  selectedRoom,
  inviteLink,
  user,
  onCopyLink,
}: MobileWebRoomConversationHeaderProps) {
  return (
    <header
      className="flex shrink-0 items-center gap-2 border-b border-white/10 px-2 py-2"
      data-tt-mobile-room-conversation-header
    >
      <button type="button" onClick={onBack} className={ICON} aria-label="Back to Trade Rooms">
        <ChevronLeft className="h-6 w-6" strokeWidth={2.25} aria-hidden />
      </button>
      <StorageImage
        src={roomImageSrc}
        preset="room-thumb"
        localTransformWidth={80}
        fallbackToOriginal={false}
        intrinsicWidth={40}
        intrinsicHeight={40}
        alt=""
        className="h-10 w-10 shrink-0 rounded-full object-cover"
      />
      <div className="min-w-0 flex-1">
        <h2 className="truncate text-[16px] font-semibold text-[color:var(--tt-text,#f0f3f6)]">
          {roomName}
        </h2>
        {memberSummary ? (
          <p className="truncate text-[12px] text-[color:var(--tt-text-muted,#57606a)]">
            {memberSummary}
          </p>
        ) : null}
      </div>
      {canShowActions ? (
        <>
          <button
            type="button"
            onClick={onOpenNotifications}
            aria-label="Notification settings"
            className={ICON}
          >
            <span aria-hidden>{roomBellEnabled ? "🔔" : "🔕"}</span>
          </button>
          {isOwner && selectedRoom && inviteLink ? (
            <>
              <button
                type="button"
                aria-label="Room settings"
                onClick={onOpenSettings}
                className={ICON}
              >
                <span aria-hidden>⚙️</span>
              </button>
              <ShareRoomMenu
                room={selectedRoom}
                inviteLink={inviteLink}
                user={user}
                onCopyLink={onCopyLink}
                triggerClassName={ICON}
                iconClassName="h-4 w-4 text-[#4EC4E0]"
              />
            </>
          ) : !isOwner && onLeave ? (
            <button
              type="button"
              onClick={onLeave}
              className="shrink-0 rounded-md px-2 py-1.5 text-xs text-red-400 active:bg-red-500/10"
            >
              Leave
            </button>
          ) : null}
        </>
      ) : null}
    </header>
  )
}
