"use client"

import { useEffect, useState } from "react"
import { createPortal } from "react-dom"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"

type AnalyzeTradeProgressModalProps = {
  open: boolean
  percent: number
  status: string
}

export default function AnalyzeTradeProgressModal({
  open,
  percent,
  status,
}: AnalyzeTradeProgressModalProps) {
  const [mounted, setMounted] = useState(false)
  const clamped = Math.max(0, Math.min(100, percent))

  useEffect(() => {
    setMounted(true)
  }, [])

  useModalScrollLock(open)

  if (!open || !mounted) return null

  return createPortal(
    <div
      className="fixed inset-0 z-[10060] flex items-center justify-center p-4"
      role="presentation"
      aria-hidden={!open}
    >
      <div
        className="absolute inset-0 bg-black/60 backdrop-blur-md"
        aria-hidden
      />
      <div
        role="dialog"
        aria-modal="true"
        aria-live="polite"
        aria-busy="true"
        aria-label="AI trade analysis in progress"
        className="relative w-full max-w-md rounded-2xl border border-white/10 bg-gradient-to-br from-[#0f172a] via-[#132a4a] to-[#0f172a] p-6 shadow-2xl shadow-black/40 transition-opacity duration-300"
      >
        <div className="text-center">
          <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-2xl border border-emerald-400/20 bg-emerald-500/10 text-2xl">
            🧠
          </div>
          <h2 className="text-lg font-semibold text-white">AI Trade Analyst</h2>
          <p className="mt-1 text-sm text-gray-400">Analyzing your trade...</p>
        </div>

        <div className="mt-6">
          <div className="mb-2 flex items-center justify-between text-xs text-gray-400">
            <span>Progress</span>
            <span className="tabular-nums text-gray-300">{clamped}%</span>
          </div>
          <div className="h-2 overflow-hidden rounded-full bg-white/10">
            <div
              className="h-full rounded-full bg-gradient-to-r from-blue-500 via-emerald-400 to-emerald-500 transition-[width] duration-300 ease-out"
              style={{ width: `${clamped}%` }}
            />
          </div>
          <p
            key={status}
            className="mt-3 min-h-[1.25rem] text-center text-sm text-gray-300 transition-opacity duration-200"
          >
            {status}
          </p>
        </div>
      </div>
    </div>,
    document.body
  )
}
