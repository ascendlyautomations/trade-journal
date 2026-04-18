"use client"

import { useEffect, useState } from "react"

type Props = {
  open: boolean
  onClose: () => void
  /** Max that can be requested this cycle (RPC `availableToRequest`). */
  availableAmount: number
  /** Minimum request amount in USD (e.g. 100). */
  minimumAmount: number
  onSubmit: (amount: number) => Promise<{ error: string | null }>
}

function roundMoney(n: number): number {
  return Math.round(n * 100) / 100
}

export default function AffiliatePayoutRequestModal({
  open,
  onClose,
  availableAmount,
  minimumAmount,
  onSubmit,
}: Props) {
  const [amountInput, setAmountInput] = useState("")
  const [busy, setBusy] = useState(false)
  const [formError, setFormError] = useState<string | null>(null)

  useEffect(() => {
    if (!open) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- reset modal when closed
      setAmountInput("")
      setFormError(null)
      setBusy(false)
    }
  }, [open])

  if (!open) return null

  const max = roundMoney(Math.max(0, availableAmount))
  const min = roundMoney(Math.max(0, minimumAmount))

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setFormError(null)
    const raw = amountInput.trim()
    const n = parseFloat(raw)
    if (raw === "" || Number.isNaN(n) || n <= 0) {
      setFormError("Enter an amount greater than zero.")
      return
    }
    const rounded = roundMoney(n)
    if (min > 0 && rounded < min - 0.001) {
      setFormError(`Minimum request is $${min.toFixed(2)}.`)
      return
    }
    if (rounded > max + 0.001) {
      setFormError(`Amount cannot exceed available to request (${max.toFixed(2)}).`)
      return
    }

    setBusy(true)
    const { error } = await onSubmit(rounded)
    setBusy(false)
    if (error) {
      setFormError(error)
      return
    }
    onClose()
  }

  return (
    <div className="fixed inset-0 z-[90] flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm">
      <div
        className="w-full max-w-md rounded-2xl border border-white/10 bg-[#152238] p-6 text-white shadow-2xl"
        role="dialog"
        aria-modal="true"
        aria-labelledby="payout-modal-title"
      >
        <div className="flex items-start justify-between gap-3">
          <h2 id="payout-modal-title" className="text-lg font-semibold text-emerald-300">
            Request payout
          </h2>
          <button
            type="button"
            onClick={() => onClose()}
            disabled={busy}
            className="rounded-lg bg-white/10 px-3 py-1 text-sm hover:bg-white/20 disabled:opacity-50"
          >
            Close
          </button>
        </div>

        <p className="mt-2 text-sm text-gray-400">
          Available to request:{" "}
          <span className="font-semibold tabular-nums text-emerald-300">${max.toFixed(2)}</span>
          {min > 0 ? (
            <>
              {" "}
              · Minimum request:{" "}
              <span className="font-semibold tabular-nums text-amber-200">${min.toFixed(2)}</span>
            </>
          ) : null}
        </p>

        <form className="mt-5 space-y-4" onSubmit={(e) => void handleSubmit(e)}>
          {formError ? (
            <p className="rounded-lg border border-red-400/40 bg-red-500/15 px-3 py-2 text-xs text-red-100">
              {formError}
            </p>
          ) : null}

          <label className="block">
            <span className="text-xs text-gray-400">Amount (USD)</span>
            <div className="relative mt-1">
              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500">$</span>
              <input
                type="text"
                inputMode="decimal"
                autoComplete="off"
                value={amountInput}
                onChange={(e) => setAmountInput(e.target.value)}
                disabled={busy}
                className="w-full rounded-lg border border-white/15 bg-[#0f172a]/80 py-2 pl-7 pr-3 font-mono text-sm text-white placeholder:text-gray-600 focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/40 disabled:opacity-50"
                placeholder={max >= min && min > 0 ? `${min.toFixed(2)} – ${max.toFixed(2)}` : "0.00"}
              />
            </div>
          </label>

          <button
            type="submit"
            disabled={busy || max <= 0 || (min > 0 && max < min - 0.001)}
            className="w-full rounded-lg bg-gradient-to-r from-emerald-500 to-blue-500 py-2.5 text-sm font-semibold disabled:opacity-50"
          >
            {busy ? "Submitting…" : "Submit request"}
          </button>
        </form>

        <p className="mt-4 text-xs text-gray-500">
          Requests are reviewed by the team. Amount must be between the minimum and your available balance.
        </p>
      </div>
    </div>
  )
}
