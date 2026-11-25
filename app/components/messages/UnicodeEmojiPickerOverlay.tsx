"use client"

import { createPortal } from "react-dom"
import { useEffect, useState } from "react"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import { UI_MODAL_BACKDROP } from "@/lib/uiPrimitiveStyles"
import UnicodeEmojiPicker from "@/app/components/messages/UnicodeEmojiPicker.tsx"

type Props = {
  open: boolean
  onClose: () => void
  onPick: (emoji: string) => void
  theme?: "light" | "dark"
  title?: string
}

export default function UnicodeEmojiPickerOverlay({
  open,
  onClose,
  onPick,
  theme = "dark",
  title = "Pick emoji",
}: Props) {
  const [mounted, setMounted] = useState(false)

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

  return createPortal(
    <div
      className="fixed inset-0 z-[10060]"
      role="presentation"
      onClick={onClose}
    >
      <div className={UI_MODAL_BACKDROP} aria-hidden />
      <div
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className="absolute left-1/2 top-1/2 w-[min(100vw-24px,360px)] max-h-[min(80vh,520px)] -translate-x-1/2 -translate-y-1/2 overflow-hidden rounded-2xl border border-white/10 bg-card shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="border-b border-white/10 px-3 py-2 text-sm font-semibold text-gray-200">
          {title}
        </div>
        <UnicodeEmojiPicker
          theme={theme}
          className="border-0 bg-transparent shadow-none"
          onPick={(emoji) => {
            onPick(emoji)
            onClose()
          }}
        />
      </div>
    </div>,
    document.body
  )
}