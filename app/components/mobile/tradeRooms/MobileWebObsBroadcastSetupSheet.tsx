"use client"

import { createPortal } from "react-dom"
import { useEffect, useState, type ReactNode } from "react"
import { useMobileWebSheetDismiss } from "@/lib/useMobileWebSheetDismiss"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import { UI_MODAL_BACKDROP } from "@/lib/uiPrimitiveStyles"

type Props = {
  open: boolean
  onClose: () => void
  children: ReactNode
}

export default function MobileWebObsBroadcastSetupSheet({
  open,
  onClose,
  children,
}: Props) {
  const [mounted, setMounted] = useState(false)
  const dismiss = useMobileWebSheetDismiss(onClose)

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
      className="fixed inset-0 z-[10055] md:hidden"
      role="presentation"
      onClick={onClose}
    >
      <div className={UI_MODAL_BACKDROP} aria-hidden />
      <div
        role="dialog"
        aria-modal="true"
        aria-label="OBS stream setup"
        className="absolute inset-x-0 bottom-0 flex max-h-[min(92vh,720px)] flex-col overflow-hidden rounded-t-2xl border border-white/10 bg-zinc-950 text-white shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div {...dismiss}>
          <div className="flex justify-center pt-3 pb-1">
            <div className="h-1 w-10 rounded-full bg-white/20" aria-hidden />
          </div>
        </div>
        <div className="border-b border-white/10 px-4 pb-3">
          <h2 className="text-base font-semibold text-white">OBS setup</h2>
          <p className="mt-0.5 text-xs text-gray-400">
            Copy RTMP settings, start OBS, then return here or use the room bar to go live.
          </p>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto px-4 py-4">{children}</div>
        <div className="border-t border-white/10 p-4">
          <button
            type="button"
            className="w-full rounded-xl border border-white/15 px-4 py-2.5 text-sm font-semibold text-white hover:bg-white/5"
            onClick={onClose}
          >
            Done
          </button>
          <p className="mt-2 text-center text-[11px] text-gray-500">
            Closing this sheet does not end your broadcast or revoke stream credentials.
          </p>
        </div>
      </div>
    </div>,
    document.body
  )
}
