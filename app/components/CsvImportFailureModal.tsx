"use client"

import { useEffect, useState } from "react"
import { createPortal } from "react-dom"

type Props = {
  open: boolean
  submitting?: boolean
  onSubmit: () => void
  onTryAnother: () => void
  onCancel: () => void
  overlayClassName?: string
}

const TITLE = "CSV file failed to import"
const BODY =
  "We couldn't read this CSV format yet. You can submit it to TradeTraxs and we'll review it so we can support your broker/export format."

const buttonBase =
  "w-full rounded-lg px-4 text-sm font-semibold transition touch-manipulation disabled:cursor-not-allowed disabled:opacity-60 min-h-[44px] py-3"

export default function CsvImportFailureModal({
  open,
  submitting = false,
  onSubmit,
  onTryAnother,
  onCancel,
  overlayClassName,
}: Props) {
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!open) return
    const prev = document.body.style.overflow
    document.body.style.overflow = "hidden"
    return () => {
      document.body.style.overflow = prev
    }
  }, [open])

  if (!open || !mounted) return null

  return createPortal(
    <div
      className={`fixed inset-0 z-[10050] flex items-end justify-center p-4 pb-[max(1rem,env(safe-area-inset-bottom))] md:items-center md:pb-4 ${overlayClassName ?? ""}`}
      role="dialog"
      aria-modal="true"
      aria-labelledby="csv-import-failure-title"
    >
      <div
        className="absolute inset-0 bg-black/60 backdrop-blur-sm"
        aria-hidden
        onClick={() => {
          if (!submitting) onCancel()
        }}
      />
      <div
        className="relative flex w-full max-w-md max-h-[min(85vh,560px)] flex-col overflow-hidden rounded-t-2xl border border-amber-500/40 bg-[#0f172a] shadow-xl md:max-h-[min(90vh,520px)] md:rounded-xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="overflow-y-auto overscroll-contain px-5 py-5 md:px-6">
          <h3 id="csv-import-failure-title" className="text-base font-semibold text-white">
            {TITLE}
          </h3>
          <p className="mt-3 text-sm leading-relaxed text-amber-100/90">{BODY}</p>
          <div className="mt-5 flex flex-col gap-2.5">
            <button
              type="button"
              disabled={submitting}
              onClick={onSubmit}
              className={`${buttonBase} bg-gradient-to-r from-blue-500 to-teal-400 text-white hover:scale-[1.01]`}
            >
              {submitting ? "Submitting..." : "Submit CSV to TradeTraxs"}
            </button>
            <button
              type="button"
              disabled={submitting}
              onClick={onTryAnother}
              className={`${buttonBase} border border-white/20 bg-white/10 font-medium text-white hover:bg-white/15`}
            >
              Try another file
            </button>
            <button
              type="button"
              disabled={submitting}
              onClick={onCancel}
              className="min-h-[44px] w-full rounded-lg px-4 py-2.5 text-sm text-gray-400 transition touch-manipulation hover:text-gray-200 disabled:opacity-60"
            >
              Cancel
            </button>
          </div>
        </div>
      </div>
    </div>,
    document.body
  )
}
