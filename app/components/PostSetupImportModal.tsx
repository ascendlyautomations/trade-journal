"use client"

import { useEffect, useState } from "react"
import CsvImportPanel from "@/app/components/CsvImportPanel"

const CSV_INPUT_ID = "post-setup-csv-import"

type Props = {
  open: boolean
  onComplete: () => void | Promise<void>
}

export default function PostSetupImportModal({ open, onComplete }: Props) {
  const [entered, setEntered] = useState(false)

  useEffect(() => {
    if (!open) {
      setEntered(false)
      return
    }
    const id = window.requestAnimationFrame(() => setEntered(true))
    return () => window.cancelAnimationFrame(id)
  }, [open])

  if (!open) return null

  async function handleSkip() {
    await onComplete()
  }

  return (
    <div
      className={`fixed inset-0 z-[102] flex items-center justify-center px-4 py-8 transition-opacity duration-300 motion-reduce:transition-none ${
        entered ? "bg-black/75 opacity-100 backdrop-blur-md" : "bg-black/75 opacity-0 backdrop-blur-md"
      }`}
      role="presentation"
    >
      <div
        className={`relative w-full max-w-lg transform transition-all duration-300 ease-out motion-reduce:transition-none motion-reduce:transform-none ${
          entered ? "translate-y-0 scale-100 opacity-100" : "translate-y-3 scale-[0.98] opacity-0"
        }`}
        role="dialog"
        aria-modal="true"
        aria-labelledby="post-setup-import-title"
      >
        <div className="max-h-[min(90vh,760px)] overflow-y-auto rounded-2xl border border-white/15 bg-[#0f172a]/95 p-6 shadow-2xl backdrop-blur-xl md:p-8">
          <h2
            id="post-setup-import-title"
            className="text-center text-xl font-semibold tracking-tight text-white md:text-2xl"
          >
            Finish Setting Up Your Account
          </h2>
          <p className="mt-2 text-center text-sm text-emerald-200/90">
            Seamlessly import your past trades and start with real data — not a blank slate.
          </p>
          <p className="mt-4 text-center text-sm leading-relaxed text-gray-400">
            Already using another journal? Bring your data with you in seconds.
          </p>

          <ol className="mt-6 list-decimal space-y-2 pl-5 text-sm leading-relaxed text-gray-300">
            <li>Export your trades as a CSV from your current platform</li>
            <li>Upload it here</li>
            <li>We&apos;ll organize everything automatically</li>
          </ol>

          <div className="mt-8 flex flex-col gap-3 sm:flex-row sm:items-stretch">
            <label
              htmlFor={CSV_INPUT_ID}
              className="flex flex-1 cursor-pointer items-center justify-center rounded-xl bg-gradient-to-r from-blue-500 to-emerald-500 px-4 py-3 text-center text-sm font-semibold text-white shadow-lg shadow-emerald-500/15 transition hover:scale-[1.02] hover:from-blue-600 hover:to-emerald-600 motion-reduce:hover:scale-100"
            >
              Import My Trades
            </label>
            <button
              type="button"
              onClick={() => void handleSkip()}
              className="rounded-xl border border-white/20 bg-white/5 px-4 py-3 text-sm font-semibold text-gray-200 transition hover:bg-white/10 sm:min-w-[140px]"
            >
              Skip for Now
            </button>
          </div>

          <div className="mt-8 border-t border-white/10 pt-6">
            <p className="mb-4 text-xs font-medium uppercase tracking-wide text-gray-500">
              CSV upload
            </p>
            <CsvImportPanel
              compact
              fileInputId={CSV_INPUT_ID}
              onImportSuccess={() => void onComplete()}
            />
          </div>

        </div>
      </div>
    </div>
  )
}
