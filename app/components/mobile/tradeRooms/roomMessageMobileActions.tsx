"use client"

import { createPortal } from "react-dom"
import type { MouseEvent, ReactNode } from "react"
import { useEffect, useState } from "react"
import { useMobileWebLongPress } from "@/lib/useMobileWebLongPress"
import { usePhoneWebTouchTarget } from "@/lib/usePhoneWebTouchTarget"
import { useMobileWebSheetDismiss } from "@/lib/useMobileWebSheetDismiss"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import { UI_MODAL_BACKDROP } from "@/lib/uiPrimitiveStyles"
import {
  MESSAGE_REACTIONS,
  type MessageReactionEmoji,
} from "@/lib/roomMessageReactions"

export function useRoomMessageOpenActions(
  messageId: string,
  setActiveMenuId: (id: string | null) => void,
  options?: { disabled?: boolean }
) {
  const phoneWeb = usePhoneWebTouchTarget()
  const longPress = useMobileWebLongPress({
    disabled: !phoneWeb || options?.disabled,
    onLongPress: () => setActiveMenuId(messageId),
  })

  if (!phoneWeb) {
    return { phoneWeb: false as const, handlers: {} }
  }

  return {
    phoneWeb: true as const,
    handlers: {
      ...longPress.handlers,
      onContextMenu: (e: MouseEvent) => {
        e.preventDefault()
        if (options?.disabled) return
        setActiveMenuId(messageId)
      },
    },
  }
}

export function TradeRoomMessageGestureSurface({
  messageId,
  setActiveMenuId,
  disabled,
  className,
  onDoubleClick,
  domId,
  children,
}: {
  messageId: string
  setActiveMenuId: (id: string | null) => void
  disabled?: boolean
  className?: string
  onDoubleClick?: (e: MouseEvent) => void
  domId?: string
  children: ReactNode
}) {
  const { handlers } = useRoomMessageOpenActions(messageId, setActiveMenuId, {
    disabled,
  })

  return (
    <div
      id={domId}
      data-room-message-id={messageId}
      className={className}
      onDoubleClick={onDoubleClick}
      {...handlers}
    >
      {children}
    </div>
  )
}

type MobileWebRoomMessageActionSheetProps = {
  open: boolean
  onClose: () => void
  canReact: boolean
  canReply: boolean
  showEdit: boolean
  showDelete: boolean
  onReply: () => void
  onEdit?: () => void
  onDelete?: () => void
  onSelectReaction: (emoji: MessageReactionEmoji) => void
  deleting?: boolean
}

export function MobileWebRoomMessageActionSheet({
  open,
  onClose,
  canReact,
  canReply,
  showEdit,
  showDelete,
  onReply,
  onEdit,
  onDelete,
  onSelectReaction,
  deleting = false,
}: MobileWebRoomMessageActionSheetProps) {
  const [mounted, setMounted] = useState(false)
  const sheetDismiss = useMobileWebSheetDismiss(onClose)

  useEffect(() => setMounted(true), [])
  useModalScrollLock(open)

  useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, onClose])

  if (!open || !mounted) return null

  const row =
    "flex w-full min-h-11 items-center px-4 text-left text-[15px] font-medium active:bg-white/10"

  const run = (fn: () => void) => () => {
    fn()
    onClose()
  }

  return createPortal(
    <div
      className="fixed inset-0 z-[10040] md:hidden"
      role="presentation"
      onClick={onClose}
    >
      <div className={UI_MODAL_BACKDROP} aria-hidden />
      <div
        role="dialog"
        aria-modal="true"
        aria-label="Message actions"
        className="absolute inset-x-0 bottom-0 rounded-t-2xl border border-white/10 bg-[color:var(--tt-surface-elevated,#1a222c)] text-[color:var(--tt-text,#f0f3f6)] shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div {...sheetDismiss}>
          <div className="flex justify-center pt-3 pb-1">
            <div className="h-1 w-10 rounded-full bg-white/20" aria-hidden />
          </div>
        </div>
        {canReact ? (
          <div
            className="flex justify-center gap-1 border-b border-white/10 px-4 py-3"
            role="group"
            aria-label="React to message"
          >
            {MESSAGE_REACTIONS.map((emoji) => (
              <button
                key={emoji}
                type="button"
                className="flex h-11 w-11 items-center justify-center rounded-full text-xl active:bg-white/10"
                aria-label={`React with ${emoji}`}
                onClick={() => {
                  onSelectReaction(emoji)
                  onClose()
                }}
              >
                {emoji}
              </button>
            ))}
          </div>
        ) : null}
        <div className="py-1">
          {canReply ? (
            <button type="button" className={row} onClick={run(onReply)}>
              Reply
            </button>
          ) : null}
          {showEdit && onEdit ? (
            <button type="button" className={row} onClick={run(onEdit)}>
              Edit message
            </button>
          ) : null}
          {showDelete && onDelete ? (
            <button
              type="button"
              className={`${row} text-red-300`}
              disabled={deleting}
              onClick={run(onDelete)}
            >
              Delete message
            </button>
          ) : null}
          <button type="button" className={`${row} text-[#4EC4E0]`} onClick={onClose}>
            Cancel
          </button>
        </div>
        <div className="h-[max(0.75rem,env(safe-area-inset-bottom))]" />
      </div>
    </div>,
    document.body
  )
}
