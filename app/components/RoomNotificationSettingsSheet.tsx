"use client"

import { useEffect } from "react"
import { createPortal } from "react-dom"

type SectionRow = { id: string; name?: string | null }

type RoomNotificationSettingsSheetProps = {
  open: boolean
  onClose: () => void
  roomName?: string | null
  sections: SectionRow[]
  roomNotificationsEnabled: boolean
  channelPrefs: Record<string, boolean>
  savingSectionId: string | null
  savingRoomLevel: boolean
  onToggleRoomLevel: (enabled: boolean) => void
  onToggleChannel: (sectionId: string, enabled: boolean) => void
}

export default function RoomNotificationSettingsSheet({
  open,
  onClose,
  roomName,
  sections,
  roomNotificationsEnabled,
  channelPrefs,
  savingSectionId,
  savingRoomLevel,
  onToggleRoomLevel,
  onToggleChannel,
}: RoomNotificationSettingsSheetProps) {
  useEffect(() => {
    if (!open) return
    const prev = document.body.style.overflow
    document.body.style.overflow = "hidden"
    return () => {
      document.body.style.overflow = prev
    }
  }, [open])

  useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, onClose])

  if (!open || typeof document === "undefined") return null

  const label = roomName?.trim() || "Trade Room"

  return createPortal(
    <div
      className="fixed inset-0 z-[10050] flex items-end justify-center md:items-center md:p-4"
      role="presentation"
      onClick={onClose}
    >
      <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" aria-hidden />
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="room-notification-settings-title"
        className="relative z-10 flex max-h-[min(85svh,560px)] w-full max-w-md flex-col overflow-hidden rounded-t-2xl border border-white/10 bg-[#0b1f3a] text-white shadow-xl md:rounded-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex shrink-0 items-center justify-between border-b border-white/10 px-4 py-3">
          <div className="min-w-0">
            <h2
              id="room-notification-settings-title"
              className="truncate text-base font-semibold text-white"
            >
              Notification Settings
            </h2>
            <p className="truncate text-xs text-gray-400">{label}</p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="shrink-0 rounded-md p-2 text-gray-400 hover:bg-white/10 hover:text-white"
            aria-label="Close notification settings"
          >
            ✕
          </button>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto px-4 py-3">
          <label className="flex items-center justify-between gap-3 rounded-lg border border-white/10 bg-white/5 px-3 py-3">
            <div>
              <p className="text-sm font-medium text-white">Room notifications</p>
              <p className="text-xs text-gray-400">
                Master switch for all channels in this room
              </p>
            </div>
            <input
              type="checkbox"
              checked={roomNotificationsEnabled}
              disabled={savingRoomLevel}
              onChange={(e) => onToggleRoomLevel(e.target.checked)}
              className="h-4 w-4 shrink-0 accent-green-500"
              aria-label="Enable room notifications"
            />
          </label>

          {sections.length > 0 ? (
            <div className="mt-4 space-y-2">
              <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">
                Channels
              </p>
              {sections.map((section) => {
                const enabled = channelPrefs[section.id] !== false
                const saving = savingSectionId === section.id
                return (
                  <label
                    key={section.id}
                    className={`flex items-center justify-between gap-3 rounded-lg border border-white/10 px-3 py-2.5 ${
                      roomNotificationsEnabled
                        ? "bg-white/5"
                        : "bg-black/20 opacity-60"
                    }`}
                  >
                    <span className="truncate text-sm text-gray-200">
                      {section.name ?? "Channel"}
                    </span>
                    <input
                      type="checkbox"
                      checked={enabled && roomNotificationsEnabled}
                      disabled={!roomNotificationsEnabled || saving}
                      onChange={(e) =>
                        onToggleChannel(section.id, e.target.checked)
                      }
                      className="h-4 w-4 shrink-0 accent-green-500"
                      aria-label={`Notifications for ${section.name ?? "channel"}`}
                    />
                  </label>
                )
              })}
            </div>
          ) : (
            <p className="mt-4 text-sm text-gray-400">
              This room has no channels. Room-level notifications apply to all
              messages.
            </p>
          )}
        </div>

        <div className="shrink-0 border-t border-white/10 px-4 py-3">
          <p className="text-center text-xs text-gray-500">
            Changes save instantly
          </p>
        </div>
      </div>
    </div>,
    document.body
  )
}
