"use client"

import { createPortal } from "react-dom"
import { useEffect, useState, type Dispatch, type SetStateAction } from "react"
import { useMobileWebSheetDismiss } from "@/lib/useMobileWebSheetDismiss"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import { UI_MODAL_BACKDROP } from "@/lib/uiPrimitiveStyles"
import { DashboardEquityDrawdownFields } from "@/app/components/dashboard/DashboardGearSettings"
import type { GearDraftState } from "@/app/components/dashboard/dashboardGearTypes"
import ActionButton from "@/app/components/ui/ActionButton"

type Props = {
  open: boolean
  accountName: string
  gearDraft: GearDraftState | null
  setGearDraft: Dispatch<SetStateAction<GearDraftState | null>>
  ddInputFocused: boolean
  setDdInputFocused: (focused: boolean) => void
  saving: boolean
  hasUser: boolean
  onSave: () => void
  onCancel: () => void
}

export default function MobileWebDashboardEquityDrawdownSettingsSheet({
  open,
  accountName,
  gearDraft,
  setGearDraft,
  ddInputFocused,
  setDdInputFocused,
  saving,
  hasUser,
  onSave,
  onCancel,
}: Props) {
  const [mounted, setMounted] = useState(false)
  const dismiss = useMobileWebSheetDismiss(onCancel)

  useEffect(() => setMounted(true), [])
  useModalScrollLock(open)

  useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onCancel()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, onCancel])

  if (!open || !mounted) return null

  return createPortal(
    <div
      className="fixed inset-0 z-[10060] md:hidden"
      role="presentation"
      onClick={onCancel}
    >
      <div className={UI_MODAL_BACKDROP} aria-hidden />
      <div
        role="dialog"
        aria-modal="true"
        aria-label="Equity curve settings"
        className="absolute inset-x-0 bottom-0 max-h-[min(85vh,520px)] overflow-hidden rounded-t-2xl border border-white/10 bg-[#0b1f3a] text-white shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div {...dismiss}>
          <div className="flex justify-center pt-3 pb-1">
            <div className="h-1 w-10 rounded-full bg-white/20" aria-hidden />
          </div>
        </div>
        <div className="border-b border-white/10 px-4 pb-3">
          <h2 className="text-base font-semibold text-white">Equity curve</h2>
          <p className="mt-0.5 text-xs text-gray-400">{accountName}</p>
        </div>
        <div className="overflow-y-auto px-4 py-4">
          <DashboardEquityDrawdownFields
            gearDraft={gearDraft}
            setGearDraft={setGearDraft}
            ddInputFocused={ddInputFocused}
            setDdInputFocused={setDdInputFocused}
            hasUser={hasUser}
            livePersonalDrawdown
            inputId="dashboard-equity-dd-mobile"
          />
        </div>
        <div className="flex gap-2 border-t border-white/10 px-4 py-3">
          <button
            type="button"
            onClick={onCancel}
            disabled={saving}
            className="flex-1 min-h-11 rounded-lg border border-white/15 bg-white/5 text-sm font-medium text-gray-200"
          >
            Cancel
          </button>
          <ActionButton
            type="button"
            onClick={onSave}
            disabled={!hasUser}
            syncing={saving}
            syncingLabel="Saving…"
            className="flex-1 min-h-11 rounded-lg bg-blue-500 text-sm font-semibold text-white"
          >
            Save
          </ActionButton>
        </div>
        <div className="h-[max(0.75rem,env(safe-area-inset-bottom))]" />
      </div>
    </div>,
    document.body
  )
}
