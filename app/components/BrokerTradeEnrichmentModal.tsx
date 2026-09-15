"use client"

import { useEffect, useState } from "react"
import Link from "next/link"
import ScrollableModalShell from "@/app/components/ui/ScrollableModalShell"
import {
  brokerEnrichmentAccountLine,
  brokerEnrichmentContractsLine,
  brokerEnrichmentPnlLine,
  brokerEnrichmentTimeRangeLine,
  brokerEnrichmentTradeHeadline,
} from "@/lib/brokerEnrichment/brokerEnrichmentTradeDisplay"
import type { BrokerEnrichmentTradeRow } from "@/lib/brokerEnrichment/brokerEnrichmentTypes"
import {
  dismissBrokerTradeEnrichment,
  saveBrokerTradeEnrichment,
} from "@/lib/brokerEnrichment/brokerEnrichmentApi"
import { supabase } from "@/lib/supabaseClient"
import { READABLE_FIELD_LABEL_CLASS, READABLE_PLACEHOLDER_CLASS } from "@/lib/readableTextStyles"
import { cn } from "@/app/components/ui/cn"

type Props = {
  open: boolean
  trades: BrokerEnrichmentTradeRow[]
  index: number
  userId: string
  onClose: () => void
  onAdvance: (completedTradeId: string) => void
  importCountLabel?: string | null
}

const inputClass = cn(
  "mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-white focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/30",
  READABLE_PLACEHOLDER_CLASS
)

export default function BrokerTradeEnrichmentModal({
  open,
  trades,
  index,
  userId,
  onClose,
  onAdvance,
  importCountLabel,
}: Props) {
  const trade = trades[index] ?? null
  const [rr, setRr] = useState("")
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!trade) return
    setRr(trade.rr != null ? String(trade.rr) : "")
    setNotes(trade.notes?.trim() ?? "")
    setError(null)
  }, [trade?.id, trade])

  if (!open || !trade) return null

  const multi = trades.length > 1
  const title = multi ? `Trade ${index + 1} of ${trades.length}` : "Finish your trade"

  async function handleSave() {
    const tradeId = trade.id
    setSaving(true)
    setError(null)
    const result = await saveBrokerTradeEnrichment(supabase, userId, tradeId, {
      rr,
      notes,
    })
    setSaving(false)
    if (!result.ok) {
      setError(result.message)
      return
    }
    onAdvance(tradeId)
  }

  async function handleDismiss() {
    const tradeId = trade.id
    setSaving(true)
    await dismissBrokerTradeEnrichment(supabase, userId, tradeId)
    setSaving(false)
    onAdvance(tradeId)
  }

  return (
    <ScrollableModalShell
      open={open}
      onClose={onClose}
      ariaLabel="Finish imported trade"
      overlayClassName="z-[110] bg-black/60 backdrop-blur-sm"
      panelClassName="max-w-lg rounded-2xl border-white/10 bg-[#152238]"
      header={
        <>
          {importCountLabel ? (
            <p className="text-sm font-medium text-emerald-300">{importCountLabel}</p>
          ) : null}
          <h2 className="text-lg font-semibold text-white">{title}</h2>
          <p className="mt-1 text-sm text-gray-400">Finish your trade</p>
        </>
      }
      footer={
        <div className="flex flex-col gap-3">
          <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-between sm:items-center">
            <button
              type="button"
              className="text-sm text-gray-400 hover:text-gray-200 disabled:opacity-50"
              disabled={saving}
              onClick={() => void handleDismiss()}
            >
              Don&apos;t ask again for this trade
            </button>
            <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
              <button
                type="button"
                className="rounded-xl border border-white/15 px-4 py-2.5 text-sm text-gray-200"
                disabled={saving}
                onClick={onClose}
              >
                Skip for now
              </button>
              <button
                type="button"
                className="rounded-xl bg-blue-500 px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-50"
                disabled={saving}
                onClick={() => void handleSave()}
              >
                {saving ? "Saving…" : multi ? "Save & next" : "Save"}
              </button>
            </div>
          </div>
        </div>
      }
    >
      <div className="space-y-4 px-1">
        <div className="rounded-xl border border-white/10 bg-black/25 p-4 space-y-2">
          <p className="text-xs uppercase tracking-wide text-gray-500">Tradovate · {brokerEnrichmentAccountLine(trade)}</p>
          <p className="text-lg font-semibold text-white">{brokerEnrichmentTradeHeadline(trade)}</p>
          <p className="text-base text-emerald-200">{brokerEnrichmentPnlLine(trade)}</p>
          <p className="text-sm text-gray-300">{brokerEnrichmentContractsLine(trade)}</p>
          <p className="text-sm text-gray-400">{brokerEnrichmentTimeRangeLine(trade)}</p>
        </div>

        <label className="block">
          <span className={READABLE_FIELD_LABEL_CLASS}>RR</span>
          <input
            type="text"
            inputMode="decimal"
            className={inputClass}
            placeholder="e.g. 2.5"
            value={rr}
            onChange={(e) => setRr(e.target.value)}
            autoComplete="off"
          />
        </label>

        <label className="block">
          <span className={READABLE_FIELD_LABEL_CLASS}>Notes</span>
          <textarea
            className={cn(inputClass, "min-h-[100px] resize-y")}
            placeholder="What happened on this trade?"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
          />
        </label>

        <Link
          href={`/trade/${trade.id}`}
          className="inline-block text-sm text-blue-300 hover:text-blue-200"
          onClick={onClose}
        >
          More details →
        </Link>

        {error ? <p className="text-sm text-red-300">{error}</p> : null}
      </div>
    </ScrollableModalShell>
  )
}
