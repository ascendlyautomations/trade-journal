"use client"

import {
  canDeleteRoomMessage,
  canEditRoomMessage,
  canModerateRoomMessage,
} from "@/lib/roomModeration"

type RoomMessageActionsMenuProps = {
  message: { id: string; user_id: string; type?: string | null }
  viewerUserId: string | null | undefined
  isRoomOwner: boolean
  activeMenuId: string | null
  setActiveMenuId: (id: string | null) => void
  onEdit: () => void
  onDelete: () => void
  deleting?: boolean
}

export default function RoomMessageActionsMenu({
  message,
  viewerUserId,
  isRoomOwner,
  activeMenuId,
  setActiveMenuId,
  onEdit,
  onDelete,
  deleting = false,
}: RoomMessageActionsMenuProps) {
  if (!canModerateRoomMessage(viewerUserId, message, { isRoomOwner })) {
    return null
  }

  const showEdit = canEditRoomMessage(viewerUserId, message)
  const showDelete = canDeleteRoomMessage(viewerUserId, message, { isRoomOwner })
  const menuOpen = activeMenuId === message.id

  return (
    <div className="relative ml-auto shrink-0">
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation()
          setActiveMenuId(menuOpen ? null : message.id)
        }}
        className={`rounded px-1.5 py-0.5 text-xs text-gray-400 transition-opacity hover:text-gray-200 ${
          menuOpen ? "opacity-100" : "opacity-0 group-hover:opacity-100"
        }`}
        aria-label="Message actions"
      >
        ⋯
      </button>

      {menuOpen ? (
        <div className="absolute right-0 top-7 z-50 w-40 rounded-lg border border-gray-600 bg-[#1e293b] shadow-lg">
          {showEdit ? (
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation()
                onEdit()
              }}
              className="w-full px-3 py-2 text-left text-sm hover:bg-white/10"
            >
              Edit Message
            </button>
          ) : null}
          {showDelete ? (
            <button
              type="button"
              disabled={deleting}
              onClick={(e) => {
                e.stopPropagation()
                onDelete()
              }}
              className="w-full px-3 py-2 text-left text-sm hover:bg-white/10 disabled:opacity-50"
            >
              {deleting ? "Deleting…" : "Delete Message"}
            </button>
          ) : null}
        </div>
      ) : null}
    </div>
  )
}
