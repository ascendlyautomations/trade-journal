"use client"

import { useEffect, useState } from "react"
import { createPortal } from "react-dom"
import ModalCloseButton from "@/app/components/ui/ModalCloseButton"
import NativeDateInput from "@/app/components/ui/NativeDateInput"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import {
  DASHBOARD_ALL_TIMEFRAME_LABEL,
  DASHBOARD_PRESET_LABEL_TO_VALUE,
  DASHBOARD_PRESET_TIMEFRAME_LABELS,
  DASHBOARD_TF_LABEL_FROM_VALUE,
} from "@/lib/dashboardTimeframeLabels"

export type DashboardTimeframePickerProps = {
  open: boolean
  onClose: () => void
  /** `sheet` = native bottom sheet; `modal` = existing centered web dialog. */
  presentation?: "sheet" | "modal"
  timeframe: string
  onTimeframeChange: (value: string) => void
  selectedDate: string
  onSelectedDateChange: (value: string) => void
  customRangeStart?: string
  customRangeEnd?: string
  onCustomRangeApply?: (start: string, end: string) => void
}

/**
 * Existing Dashboard timeframe controls — shared by TradeFilterBar (web) and
 * the native iOS timeframe sheet. Behavior unchanged; only chrome differs.
 */
export default function DashboardTimeframePicker({
  open,
  onClose,
  presentation = "modal",
  timeframe,
  onTimeframeChange,
  selectedDate,
  onSelectedDateChange,
  customRangeStart = "",
  customRangeEnd = "",
  onCustomRangeApply,
}: DashboardTimeframePickerProps) {
  const [startDate, setStartDate] = useState("")
  const [endDate, setEndDate] = useState("")

  useModalScrollLock(open && presentation === "sheet")

  useEffect(() => {
    if (!open) return
    if (timeframe === "custom") {
      setStartDate(customRangeStart)
      setEndDate(customRangeEnd)
    } else if (selectedDate?.trim()) {
      setStartDate(selectedDate)
      setEndDate(selectedDate)
    } else {
      setStartDate("")
      setEndDate("")
    }
  }, [open, timeframe, selectedDate, customRangeStart, customRangeEnd])

  useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, onClose])

  if (!open) return null

  const body = (
    <>
      <div className="grid grid-cols-2 gap-3 mb-4">
        {DASHBOARD_PRESET_TIMEFRAME_LABELS.map((tf) => (
          <button
            key={tf}
            type="button"
            onClick={() => {
              const v = DASHBOARD_PRESET_LABEL_TO_VALUE[tf]
              onSelectedDateChange("")
              onTimeframeChange(v)
              onClose()
            }}
            className="px-3 py-2.5 rounded-xl bg-white/10 hover:bg-green-500/20 text-white text-sm font-medium"
          >
            {tf}
          </button>
        ))}
      </div>

      <div className="mt-5">
        <p className="mb-2 text-sm text-gray-400">Specific Date</p>
        <NativeDateInput
          value={startDate}
          onChange={(e) => {
            const v = e.target.value
            setStartDate(v)
            setEndDate(v)
          }}
          className="h-11 rounded-xl border border-blue-400/20 bg-[#0b2345] shadow-inner shadow-black/20 transition hover:border-blue-300/40 focus-within:border-emerald-400/60 focus-within:ring-2 focus-within:ring-emerald-500/30"
          aria-label="Specific date"
        />
        <button
          type="button"
          onClick={() => {
            if (!startDate?.trim()) return
            onSelectedDateChange(startDate)
            setEndDate(startDate)
            onTimeframeChange("all")
            onClose()
          }}
          className="w-full mt-2 py-2.5 rounded-xl bg-blue-500 text-white font-medium hover:bg-blue-600 disabled:hover:bg-blue-500"
        >
          Apply Specific Date
        </button>
      </div>

      <div className="mt-5">
        <p className="mb-2 text-sm text-gray-400">Custom Range</p>
        <div className="flex items-center gap-2 overflow-visible">
          <NativeDateInput
            value={startDate}
            onChange={(e) => setStartDate(e.target.value)}
            className="h-11 min-w-0 flex-1 rounded-xl border border-blue-400/20 bg-[#0b2345] shadow-inner shadow-black/20 transition hover:border-blue-300/40 focus-within:border-emerald-400/60 focus-within:ring-2 focus-within:ring-emerald-500/30"
            aria-label="Range start date"
          />
          <NativeDateInput
            value={endDate}
            onChange={(e) => setEndDate(e.target.value)}
            className="h-11 min-w-0 flex-1 rounded-xl border border-blue-400/20 bg-[#0b2345] shadow-inner shadow-black/20 transition hover:border-blue-300/40 focus-within:border-emerald-400/60 focus-within:ring-2 focus-within:ring-emerald-500/30"
            aria-label="Range end date"
          />
        </div>
        <button
          type="button"
          onClick={() => {
            if (!startDate?.trim() || !endDate?.trim()) return
            onSelectedDateChange("")
            onCustomRangeApply?.(startDate, endDate)
            onClose()
          }}
          className="w-full mt-2 py-2.5 rounded-xl bg-blue-500 text-white font-medium hover:bg-blue-600 disabled:hover:bg-blue-500"
        >
          Apply Range
        </button>
      </div>

      <button
        type="button"
        onClick={() => {
          setStartDate("")
          setEndDate("")
          onSelectedDateChange("")
          onTimeframeChange("all")
          onClose()
        }}
        className="w-full mt-4 py-2.5 rounded-xl bg-white/10 hover:bg-white/20 text-white text-sm"
      >
        Clear Dates
      </button>

      <button
        type="button"
        onClick={onClose}
        className="mt-4 w-full text-sm text-gray-400 hover:text-white"
      >
        Cancel
      </button>
    </>
  )

  if (presentation === "sheet") {
    if (typeof document === "undefined") return null
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
          aria-labelledby="dashboard-timeframe-sheet-title"
          className="relative z-10 flex max-h-[min(88svh,640px)] w-full flex-col overflow-hidden rounded-t-2xl border border-white/10 bg-[#0b1f3a] text-white shadow-xl pb-[var(--safe-area-bottom)]"
          onClick={(e) => e.stopPropagation()}
        >
          <div className="mx-auto mt-2 h-1 w-10 shrink-0 rounded-full bg-white/25" aria-hidden />
          <div className="flex shrink-0 items-center justify-between border-b border-white/10 px-4 py-3">
            <h2
              id="dashboard-timeframe-sheet-title"
              className="text-base font-semibold text-white"
            >
              Select Timeframe
            </h2>
            <ModalCloseButton onClick={onClose} />
          </div>
          <div className="min-h-0 flex-1 overflow-y-auto px-4 py-4">{body}</div>
        </div>
      </div>,
      document.body
    )
  }

  return (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/50 backdrop-blur-sm">
      <div className="relative w-full max-w-md bg-[#0b1f3a] rounded-2xl p-6 border border-white/10 shadow-xl">
        <ModalCloseButton
          onClick={onClose}
          className="absolute right-4 top-4 z-10"
        />
        <h2 className="text-lg font-semibold text-white mb-4 pr-12">
          Select Timeframe
        </h2>
        {body}
      </div>
    </div>
  )
}

/** Display label sync helper for filter bar button text. */
export function syncTimeframeDisplayLabel(
  timeframe: string,
  selectedDate: string
): string {
  if (timeframe === "custom") return "Custom"
  if (selectedDate?.trim()) return "Specific Date"
  return DASHBOARD_TF_LABEL_FROM_VALUE[timeframe] ?? DASHBOARD_ALL_TIMEFRAME_LABEL
}
