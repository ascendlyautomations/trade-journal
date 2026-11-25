"use client"

import { createPortal } from "react-dom"
import { useEffect, useState } from "react"
import { useMobileWebSheetDismiss } from "@/lib/useMobileWebSheetDismiss"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import { UI_MODAL_BACKDROP } from "@/lib/uiPrimitiveStyles"
import UnicodeEmojiPickerOverlay from "@/app/components/messages/UnicodeEmojiPickerOverlay.tsx"

type Props = {
  open: boolean
  onClose: () => void
  canReply: boolean
  canReact: boolean
  onReply: () => void
  onSelectReaction: (emoji: string) => void
}

export default function BroadcastChatMessageActionSheet({
  open,
  onClose,
  canReply,
  canReact,
  onReply,
  onSelectReaction,
}: Props) {
  const [mounted, setMounted] = useState(false)
  const [pickerOpen, setPickerOpen] = useState(false)
  const sheetDismiss = useMobileWebSheetDismiss(onClose)

  useEffect(() => setMounted(true), [])
  useModalScrollLock(open || pickerOpen)

  useEffect(() => {
    if (!open) setPickerOpen(false)
  }, [open])

  const pick = (emoji: string) => {
    onSelectReaction(emoji)
    onClose()
    setPickerOpen(false)
  }

  if (!mounted) return null

  return (
    <>
      {open ? (
        createPortal(
          <div
            className="fixed inset-0 z-[10040]"
            role="presentation"
            onClick={onClose}
          >
            <div className={UI_MODAL_BACKDROP} aria-hidden />
            <div
              role="dialog"
              aria-modal
              aria-label="Chat message actions"
              className="absolute inset-x-0 bottom-0 rounded-t-2xl border border-white/10 bg-[#12141a] p-3 pb-6 text-white shadow-2xl"
              onClick={(e) => e.stopPropagation()}
            >
              <div {...sheetDismiss}>
                <div className="mx-auto mb-3 h-1 w-10 rounded-full bg-white/20" />
              </div>
              <ul className="space-y-1 text-sm">
                {canReply ? (
                  <li>
                    <button
                      type="button"
                      className="flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-left hover:bg-white/10"
                      onClick={() => {
                        onReply()
                        onClose()
                      }}
                    >
                      <span aria-hidden>↩️</span>
                      Reply
                    </button>
                  </li>
                ) : null}
                {canReact ? (
                  <li>
                    <button
                      type="button"
                      className="flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-left hover:bg-white/10"
                      onClick={() => setPickerOpen(true)}
                    >
                      <span aria-hidden>😊</span>
                      Reaction
                    </button>
                  </li>
                ) : null}
              </ul>
            </div>
          </div>,
          document.body
        )
      ) : null}
      <UnicodeEmojiPickerOverlay
        open={pickerOpen}
        onClose={() => setPickerOpen(false)}
        onPick={pick}
        theme="dark"
      />
    </>
  )
}