"use client"

import { useEffect, useState, type Dispatch, type SetStateAction } from "react"
import { createPortal } from "react-dom"
import ModalCloseButton from "@/app/components/ui/ModalCloseButton"
import CustomSelect from "@/app/components/CustomSelect"
import DashboardTimeframePicker from "@/app/components/dashboard/DashboardTimeframePicker"
import DashboardGearSettings from "@/app/components/dashboard/DashboardGearSettings"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import { SELECT_FILTER_TRIGGER_CLASS } from "@/lib/accountDropdownStyles"
import { dashboardTimeframeCapsuleLabel } from "@/lib/dashboardTimeframeLabels"
import type { GearDraftState } from "@/app/components/dashboard/dashboardGearTypes"
import { hapticLight } from "@/lib/nativeHaptics"
import { DASHBOARD_MOBILE_ACTION_BTN_CLASS } from "@/app/components/dashboard/dashboardHeaderMobileUi"

const MODE_OPTIONS = [
  { label: "All Modes", value: "all" },
  { label: "Live", value: "live" },
  { label: "Funded", value: "funded" },
  { label: "Eval", value: "eval" },
] as const

export type NativeIosDashboardFilterSheetProps = {
  open: boolean
  onClose: () => void
  accountTypeFilter: string
  onAccountTypeChange: (value: string) => void
  timeframe: string
  onTimeframeChange: (value: string) => void
  customRangeStart: string
  customRangeEnd: string
  onCustomRangeApply: (start: string, end: string) => void
  selectedDate: string
  onSelectedDateChange: (value: string) => void
  showPublicOnly: boolean
  onTogglePublicOnly: () => void
  onOpenPerformanceShare: () => void
  showShareControls: boolean
  showTradingReportButton: boolean
  onOpenTradingReport?: () => void
  showControls: boolean
  onToggleShowControls: () => void
  gearDraft: GearDraftState | null
  setGearDraft: Dispatch<SetStateAction<GearDraftState | null>>
  ddInputFocused: boolean
  setDdInputFocused: (focused: boolean) => void
  savingGearSettings: boolean
  hasUser: boolean
  onSaveGear: () => void
  onCancelGear: () => void
}

/**
 * Native Dashboard filter sheet — timeframe, mode, public, share/report, preferences.
 * Account picker stays on the action bar (outside this sheet).
 */
export default function NativeIosDashboardFilterSheet({
  open,
  onClose,
  accountTypeFilter,
  onAccountTypeChange,
  timeframe,
  onTimeframeChange,
  customRangeStart,
  customRangeEnd,
  onCustomRangeApply,
  selectedDate,
  onSelectedDateChange,
  showPublicOnly,
  onTogglePublicOnly,
  onOpenPerformanceShare,
  showShareControls,
  showTradingReportButton,
  onOpenTradingReport,
  showControls,
  onToggleShowControls,
  gearDraft,
  setGearDraft,
  ddInputFocused,
  setDdInputFocused,
  savingGearSettings,
  hasUser,
  onSaveGear,
  onCancelGear,
}: NativeIosDashboardFilterSheetProps) {
  const [timeframePickerOpen, setTimeframePickerOpen] = useState(false)

  useModalScrollLock(open)

  useEffect(() => {
    if (!open) {
      setTimeframePickerOpen(false)
      return
    }
    if (!showControls) onToggleShowControls()
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, showControls, onToggleShowControls, onClose])

  if (!open || typeof document === "undefined") return null

  const timeframeLabel = dashboardTimeframeCapsuleLabel({
    timeframe,
    selectedDate,
    customRangeStart,
    customRangeEnd,
  })

  return createPortal(
    <div
      className="fixed inset-0 z-[10050] flex items-end justify-center"
      role="presentation"
      onClick={onClose}
    >
      <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" aria-hidden />
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="native-dashboard-filter-title"
        className="relative z-10 flex max-h-[min(88svh,640px)] w-full flex-col overflow-hidden rounded-t-2xl border border-white/10 bg-[#0b1f3a] text-white shadow-xl pb-[var(--safe-area-bottom)]"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mx-auto mt-2 h-1 w-10 shrink-0 rounded-full bg-white/25" aria-hidden />
        <div className="flex shrink-0 items-center justify-between border-b border-white/10 px-4 py-3">
          <h2
            id="native-dashboard-filter-title"
            className="text-base font-semibold text-white"
          >
            Filters
          </h2>
          <ModalCloseButton onClick={onClose} />
        </div>

        <div className="min-h-0 flex-1 space-y-5 overflow-y-auto px-4 py-4">
          <section>
            <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-white/45">
              Mode
            </p>
            <CustomSelect
              value={accountTypeFilter}
              onChange={onAccountTypeChange}
              className="w-full"
              triggerClassName={SELECT_FILTER_TRIGGER_CLASS}
              options={[...MODE_OPTIONS]}
            />
          </section>

          <section>
            <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-white/45">
              Timeframe
            </p>
            <button
              type="button"
              onClick={() => {
                hapticLight("timeframe")
                setTimeframePickerOpen(true)
              }}
              className="inline-flex h-10 w-full items-center justify-between rounded-xl border border-white/15 bg-white/10 px-3 text-sm font-medium text-white"
            >
              <span className="truncate">{timeframeLabel}</span>
              <span className="text-white/50" aria-hidden>
                ›
              </span>
            </button>
          </section>

          {showShareControls ? (
            <section className="space-y-2">
              <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-white/45">
                Visibility
              </p>
              <button
                type="button"
                onClick={() => {
                  hapticLight("public")
                  onTogglePublicOnly()
                }}
                className={`flex h-11 w-full items-center justify-between rounded-xl px-3 text-sm font-medium ${
                  showPublicOnly
                    ? "bg-blue-500/90 text-white"
                    : "bg-white/5 text-white/80"
                }`}
              >
                <span>Public trades only</span>
                <span className="text-xs opacity-80">
                  {showPublicOnly ? "On" : "Off"}
                </span>
              </button>
            </section>
          ) : null}

          <section className="space-y-2">
            <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-white/45">
              Actions
            </p>
            {showTradingReportButton && onOpenTradingReport ? (
              <button
                type="button"
                onClick={() => {
                  hapticLight("report")
                  onOpenTradingReport()
                  onClose()
                }}
                className={`${DASHBOARD_MOBILE_ACTION_BTN_CLASS} w-full`}
              >
                Report
              </button>
            ) : null}
            {showShareControls ? (
              <button
                type="button"
                onClick={() => {
                  hapticLight("share")
                  onOpenPerformanceShare()
                  onClose()
                }}
                className="flex h-11 w-full items-center rounded-xl bg-white/5 px-3 text-sm font-medium text-white/80 active:bg-white/10"
              >
                Share performance
              </button>
            ) : null}
          </section>

          <section>
            <DashboardGearSettings
              embedded
              showControls
              onToggleShowControls={onToggleShowControls}
              gearDraft={gearDraft}
              setGearDraft={setGearDraft}
              ddInputFocused={ddInputFocused}
              setDdInputFocused={setDdInputFocused}
              savingGearSettings={savingGearSettings}
              hasUser={hasUser}
              onSaveGear={onSaveGear}
              onCancelGear={onCancelGear}
            />
          </section>

          <button
            type="button"
            onClick={onClose}
            className="w-full rounded-xl bg-white/10 py-3 text-sm font-semibold text-white"
          >
            Done
          </button>
        </div>
      </div>

      <DashboardTimeframePicker
        open={timeframePickerOpen}
        onClose={() => setTimeframePickerOpen(false)}
        presentation="sheet"
        timeframe={timeframe}
        onTimeframeChange={onTimeframeChange}
        selectedDate={selectedDate}
        onSelectedDateChange={onSelectedDateChange}
        customRangeStart={customRangeStart}
        customRangeEnd={customRangeEnd}
        onCustomRangeApply={onCustomRangeApply}
      />
    </div>,
    document.body
  )
}
