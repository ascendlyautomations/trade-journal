"use client"

import { useState } from "react"
import CsvImportPanel from "../components/CsvImportPanel"
import QuickTradeModal from "../components/QuickTradeModal"
import type { QuickTradeCsvFormPatch } from "@/lib/parseQuickCsvPaste"
import { useUserProfile } from "@/lib/useUserProfile"

export default function ImportPage() {
  const { user } = useUserProfile()
  const [showQuickTrade, setShowQuickTrade] = useState(false)
  const [quickTradeInitialPatch, setQuickTradeInitialPatch] =
    useState<QuickTradeCsvFormPatch | null>(null)

  return (
    <>
      <div className="min-h-screen bg-[#0f172a] p-6 text-white">
        <div className="mx-auto max-w-4xl">
          <h1 className="mb-4 text-2xl text-blue-300">Import Trades</h1>
          <CsvImportPanel
            onSingleTradeDetected={(patch) => {
              setQuickTradeInitialPatch(patch)
              setShowQuickTrade(true)
            }}
          />
        </div>
      </div>

      <QuickTradeModal
        open={showQuickTrade}
        userId={user?.id ?? null}
        initialCsvPatch={quickTradeInitialPatch}
        onClose={() => {
          setShowQuickTrade(false)
          setQuickTradeInitialPatch(null)
        }}
      />
    </>
  )
}
