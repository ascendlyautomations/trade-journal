"use client"

import { useEffect, useState } from "react"
import Modal from "@/app/components/ui/Modal"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import { ProfileLink } from "@/app/components/ProfileLink"

type Member = {
  user_id: string
  profiles?: {
    id?: string | null
    username?: string | null
    avatar_url?: string | null
  } | null
}

export type ConversationSettingsModalProps = {
  open: boolean
  onClose: () => void
  isGroup: boolean
  title: string
  notificationsEnabled: boolean
  notificationsSaving?: boolean
  onNotificationsChange: (enabled: boolean) => void
  isPinned: boolean
  pinSaving?: boolean
  onPinChange: (pinned: boolean) => void
  members: Member[]
  onViewSharedMedia: () => void
  blockedByMe?: boolean
  blockedByOther?: boolean
  blockStatusLoading?: boolean
  onBlockUserChange?: (blocked: boolean) => void
  onInviteMembers?: () => void
  onLeaveConversation: () => void
  leaveLabel: string
  leaveBusy?: boolean
  /** Group name + avatar editing (groups only). */
  groupName?: string
  onGroupNameChange?: (name: string) => void
  groupAvatarUrl?: string | null
  groupAvatarPreviewUrl?: string | null
  onGroupAvatarChange?: (e: React.ChangeEvent<HTMLInputElement>) => void
  onSaveGroupDetails?: () => void
  groupDetailsSaving?: boolean
}

function SettingsToggle({
  label,
  description,
  checked,
  disabled,
  onChange,
}: {
  label: string
  description?: string
  checked: boolean
  disabled?: boolean
  onChange: (next: boolean) => void
}) {
  return (
    <div
      className={`flex items-start justify-between gap-4 py-3 ${
        disabled ? "opacity-45" : ""
      }`}
    >
      <div className="min-w-0">
        <p className="text-sm font-medium text-white">{label}</p>
        {description ? (
          <p className="mt-0.5 text-xs leading-relaxed text-gray-400">
            {description}
          </p>
        ) : null}
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={label}
        disabled={disabled}
        onClick={() => onChange(!checked)}
        className={`relative mt-0.5 h-6 w-11 shrink-0 rounded-full transition-colors disabled:cursor-not-allowed ${
          checked ? "bg-blue-500" : "bg-white/20"
        }`}
      >
        <span
          className={`absolute top-0.5 left-0.5 h-5 w-5 rounded-full bg-white shadow transition-transform ${
            checked ? "translate-x-5" : "translate-x-0"
          }`}
        />
      </button>
    </div>
  )
}

export default function ConversationSettingsModal({
  open,
  onClose,
  isGroup,
  title,
  notificationsEnabled,
  notificationsSaving = false,
  onNotificationsChange,
  isPinned,
  pinSaving = false,
  onPinChange,
  members,
  onViewSharedMedia,
  blockedByMe = false,
  blockedByOther = false,
  blockStatusLoading = false,
  onBlockUserChange,
  onInviteMembers,
  onLeaveConversation,
  leaveLabel,
  leaveBusy = false,
  groupName = "",
  onGroupNameChange,
  groupAvatarUrl = null,
  groupAvatarPreviewUrl = null,
  onGroupAvatarChange,
  onSaveGroupDetails,
  groupDetailsSaving = false,
}: ConversationSettingsModalProps) {
  const [showMembers, setShowMembers] = useState(false)

  useEffect(() => {
    if (open) return
    const frame = requestAnimationFrame(() => setShowMembers(false))
    return () => cancelAnimationFrame(frame)
  }, [open])

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Conversation Settings"
      size="md"
      belowNavbar
      panelClassName="max-h-[calc(100vh-5rem)] overflow-hidden"
      bodyClassName="space-y-5"
    >
      <p className="text-sm text-gray-400">
        {isGroup ? "Group chat" : "Direct message"} · {title}
      </p>

      <section className="rounded-xl border border-white/10 bg-white/5 px-4">
        <SettingsToggle
          label="Notifications"
          description={
            notificationsEnabled
              ? "On — new messages can show badges for this chat."
              : "Off (Muted) — no badges for new messages. Chat still updates when opened."
          }
          checked={notificationsEnabled}
          disabled={notificationsSaving}
          onChange={onNotificationsChange}
        />
        <div className="border-t border-white/5">
          <SettingsToggle
            label="Pin Conversation"
            description="Keep this chat at the top of your Messages list."
            checked={isPinned}
            disabled={pinSaving}
            onChange={onPinChange}
          />
        </div>
      </section>

      {isGroup ? (
        <section className="space-y-3 rounded-xl border border-white/10 bg-white/5 p-4">
          <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">
            Group Details
          </p>
          <div className="flex items-center gap-3">
            <img
              src={
                groupAvatarPreviewUrl ||
                groupAvatarUrl ||
                "/group-default.png"
              }
              alt=""
              className="h-14 w-14 rounded-full object-cover border border-white/10"
              onError={(e) => {
                e.currentTarget.src = "/group-default.png"
              }}
            />
            {onGroupAvatarChange ? (
              <input
                type="file"
                accept="image/*"
                onChange={onGroupAvatarChange}
                className="text-xs text-gray-300"
              />
            ) : null}
          </div>
          {onGroupNameChange ? (
            <input
              value={groupName}
              onChange={(e) => onGroupNameChange(e.target.value)}
              placeholder="Group name"
              className="w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-sm text-white outline-none focus:ring-2 focus:ring-blue-500/40"
            />
          ) : null}
          {onSaveGroupDetails ? (
            <button
              type="button"
              onClick={onSaveGroupDetails}
              disabled={groupDetailsSaving}
              className="w-full rounded-lg bg-blue-500 px-4 py-2 text-sm font-medium text-white hover:bg-blue-600 disabled:opacity-50"
            >
              {groupDetailsSaving ? "Saving…" : "Save Group Details"}
            </button>
          ) : null}
        </section>
      ) : null}

      <section className="space-y-2 rounded-xl border border-white/10 bg-white/5 p-4">
        <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">
          {isGroup ? "Members" : "More"}
        </p>

        {isGroup ? (
          <>
            <button
              type="button"
              onClick={() => setShowMembers((v) => !v)}
              className="w-full rounded-lg bg-[#1e293b] px-3 py-2.5 text-left text-sm text-white hover:bg-[#334155]"
            >
              {showMembers
                ? "Hide Members"
                : `View Members (${members.length})`}
            </button>
            {showMembers ? (
              <div className="flex max-h-40 flex-wrap gap-2 overflow-y-auto pt-1">
                {members.map((m) => (
                  <ProfileLink
                    key={m.user_id}
                    userId={m.profiles?.id ?? m.user_id}
                    username={m.profiles?.username}
                    className="flex items-center gap-2 rounded-lg bg-[#1e293b] px-3 py-2 text-sm text-white hover:bg-[#334155]"
                  >
                    <ProfileAvatarImg
                      src={m.profiles?.avatar_url}
                      className="h-6 w-6"
                    />
                    <span>@{m.profiles?.username || "user"}</span>
                  </ProfileLink>
                ))}
              </div>
            ) : null}
            {onInviteMembers ? (
              <button
                type="button"
                onClick={onInviteMembers}
                className="w-full rounded-lg bg-[#1e293b] px-3 py-2.5 text-left text-sm text-white hover:bg-[#334155]"
              >
                Invite Members
              </button>
            ) : null}
          </>
        ) : null}

        <button
          type="button"
          onClick={onViewSharedMedia}
          className="w-full rounded-lg bg-[#1e293b] px-3 py-2.5 text-left text-sm text-white hover:bg-[#334155]"
        >
          View Shared Media
          <span className="mt-0.5 block text-xs text-gray-400">
            Open images shared in this conversation
          </span>
        </button>
      </section>

      <section className="space-y-2 rounded-xl border border-red-500/20 bg-red-500/5 p-4">
        
        <button
          type="button"
          onClick={onLeaveConversation}
          disabled={leaveBusy}
          className="w-full rounded-lg bg-red-500 px-3 py-2.5 text-sm font-medium text-white hover:bg-red-600 disabled:opacity-50"
        >
          {leaveBusy ? "Working…" : leaveLabel}
        </button>
        {!isGroup ? (
          <button
            type="button"
            disabled={blockStatusLoading || !onBlockUserChange}
            onClick={() => onBlockUserChange?.(!blockedByMe)}
            className="w-full rounded-lg border border-red-500/30 bg-red-500/10 px-3 py-2.5 text-sm font-medium text-red-200 hover:bg-red-500/20 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {blockStatusLoading
              ? "Checking Block Status…"
              : blockedByMe
                ? "Unblock User"
                : "Block User"}
            {blockedByOther && !blockedByMe ? (
              <span className="mt-0.5 block text-xs font-normal text-red-300/70">
                Direct messaging is already unavailable.
              </span>
            ) : null}
          </button>
        ) : (
          <button
            type="button"
            disabled
            className="w-full cursor-not-allowed rounded-lg border border-white/10 bg-white/5 px-3 py-2.5 text-left text-sm text-gray-400"
          >
            Delete Group
            <span className="mt-0.5 block text-xs text-gray-500">
              Owner-only — coming soon
            </span>
          </button>
        )}
      </section>

      <button
        type="button"
        disabled
        className="w-full cursor-not-allowed rounded-lg border border-white/10 bg-white/5 px-3 py-2.5 text-left text-sm text-gray-400"
      >
        {isGroup ? "Report Group" : "Report Conversation"}
        <span className="mt-0.5 block text-xs text-gray-500">Coming soon</span>
      </button>
    </Modal>
  )
}
